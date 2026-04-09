// ============================================================
// Project   : Real-Time EMG Gesture Recognition on FPGA
// File      : top_module.v
// Purpose   : Top-level module that connects all sub-modules
//
// This is the main file that ties everything together:
//   1. EMG Preprocessor  - filters and extracts RMS features from raw signals
//   2. NN Inference Engine - runs the trained CNN model to classify gestures
//   3. Argmax Block       - picks the gesture with the highest score
//
// Target    : Xilinx Artix-7 (xc7a35ticsg324-1L) - Arty A7-35T
// Clock     : 50 MHz
// Gestures  : 8 classes (Rest, Open, Close, Flex, Extend, Pinch, Point, Thumb)
// ============================================================

module emg_gesture_recognition_top #(
    parameter NUM_CHANNELS  = 8,   // 8 EMG electrode channels
    parameter ADC_WIDTH     = 12,  // 12-bit ADC input
    parameter NUM_CLASSES   = 8,   // 8 gesture classes
    parameter FEATURE_WIDTH = 8    // 8-bit (INT8) features after quantization
)(
    input  wire clk,           // 50 MHz system clock
    input  wire rst_n,         // Active-low reset (press button to reset)

    // --- ADC Input Interface (8 EMG channels) ---
    input  wire adc_data_valid,
    input  wire signed [ADC_WIDTH-1:0] adc_ch0,
    input  wire signed [ADC_WIDTH-1:0] adc_ch1,
    input  wire signed [ADC_WIDTH-1:0] adc_ch2,
    input  wire signed [ADC_WIDTH-1:0] adc_ch3,
    input  wire signed [ADC_WIDTH-1:0] adc_ch4,
    input  wire signed [ADC_WIDTH-1:0] adc_ch5,
    input  wire signed [ADC_WIDTH-1:0] adc_ch6,
    input  wire signed [ADC_WIDTH-1:0] adc_ch7,

    // --- Output: Predicted Gesture ---
    output reg [2:0] gesture_class,  // 0-7 gesture ID shown on LEDs
    output reg gesture_valid,         // Goes high for 1 cycle when result is ready

    // --- Debug / Status Outputs ---
    output wire preprocessing_active, // High while preprocessing is running
    output wire inference_active,      // High while neural network is running
    output reg [15:0] latency_cycles,  // Measures how many cycles inference takes
    output reg [3:0]  system_state     // Current pipeline state (for debugging)
);

    // --- Internal wires to connect modules ---

    // RMS features from preprocessor to NN engine
    wire signed [FEATURE_WIDTH-1:0] rms_ch0, rms_ch1, rms_ch2, rms_ch3;
    wire signed [FEATURE_WIDTH-1:0] rms_ch4, rms_ch5, rms_ch6, rms_ch7;
    wire rms_valid;

    // NN engine output scores (one per gesture class)
    wire signed [7:0] nn_out0, nn_out1, nn_out2, nn_out3;
    wire signed [7:0] nn_out4, nn_out5, nn_out6, nn_out7;
    wire nn_valid;

    // Argmax output
    wire [2:0] argmax_class;
    wire argmax_valid;

    // For latency counter
    reg counting;

    // ============================================================
    // MODULE 1: EMG Preprocessor
    // Takes raw 12-bit ADC values, applies high-pass filter,
    // rectification, and RMS extraction. Outputs 8-bit features.
    // ============================================================
    emg_preprocessor #(
        .NUM_CHANNELS (NUM_CHANNELS),
        .DATA_WIDTH   (ADC_WIDTH),
        .OUTPUT_WIDTH (FEATURE_WIDTH),
        .WINDOW_SIZE  (100),  // 50ms window at 2kHz
        .STEP_SIZE    (20)    // 10ms step
    ) preprocessor (
        .clk         (clk),
        .rst_n       (rst_n),
        .data_valid  (adc_data_valid),
        .adc_ch0(adc_ch0), .adc_ch1(adc_ch1),
        .adc_ch2(adc_ch2), .adc_ch3(adc_ch3),
        .adc_ch4(adc_ch4), .adc_ch5(adc_ch5),
        .adc_ch6(adc_ch6), .adc_ch7(adc_ch7),
        .rms_ch0(rms_ch0), .rms_ch1(rms_ch1),
        .rms_ch2(rms_ch2), .rms_ch3(rms_ch3),
        .rms_ch4(rms_ch4), .rms_ch5(rms_ch5),
        .rms_ch6(rms_ch6), .rms_ch7(rms_ch7),
        .rms_valid   (rms_valid)
    );

    // ============================================================
    // MODULE 2: Neural Network Inference Engine
    // Implements the trained CNN model (quantized to INT8).
    // Takes RMS features and outputs a score for each gesture class.
    // ============================================================
    nn_inference_engine #(
        .INPUT_CHANNELS (NUM_CHANNELS),
        .NUM_CLASSES    (NUM_CLASSES)
    ) nn_engine (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (rms_valid),
        .feat_ch0(rms_ch0), .feat_ch1(rms_ch1),
        .feat_ch2(rms_ch2), .feat_ch3(rms_ch3),
        .feat_ch4(rms_ch4), .feat_ch5(rms_ch5),
        .feat_ch6(rms_ch6), .feat_ch7(rms_ch7),
        .score0(nn_out0), .score1(nn_out1),
        .score2(nn_out2), .score3(nn_out3),
        .score4(nn_out4), .score5(nn_out5),
        .score6(nn_out6), .score7(nn_out7),
        .valid  (nn_valid)
    );

    // ============================================================
    // MODULE 3: Argmax - Pick the highest scoring gesture
    // Scans all 8 scores and outputs the index of the maximum.
    // ============================================================
    argmax #(
        .NUM_CLASSES (NUM_CLASSES),
        .DATA_WIDTH  (8)
    ) argmax_inst (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (nn_valid),
        .data0(nn_out0), .data1(nn_out1),
        .data2(nn_out2), .data3(nn_out3),
        .data4(nn_out4), .data5(nn_out5),
        .data6(nn_out6), .data7(nn_out7),
        .class_id (argmax_class),
        .valid    (argmax_valid)
    );

    // ============================================================
    // Output Register
    // Stores the final predicted gesture class
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gesture_class <= 3'b000;
            gesture_valid <= 1'b0;
        end else begin
            if (argmax_valid) begin
                gesture_class <= argmax_class;
                gesture_valid <= 1'b1;
            end else begin
                gesture_valid <= 1'b0;
            end
        end
    end

    // ============================================================
    // Latency Counter
    // Counts clock cycles from ADC input to gesture output
    // Helps verify we meet the <20ms real-time requirement
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latency_cycles <= 16'd0;
            counting       <= 1'b0;
        end else begin
            if (adc_data_valid && !counting) begin
                counting       <= 1'b1;
                latency_cycles <= 16'd0;
            end else if (counting) begin
                if (latency_cycles < 16'hFFFF)
                    latency_cycles <= latency_cycles + 16'd1;
                if (gesture_valid)
                    counting <= 1'b0;
            end
        end
    end

    // ============================================================
    // System State Monitor (for debugging on LEDs)
    // Bit 0: preprocessor done, Bit 1: NN done, Bit 2: argmax done
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            system_state <= 4'd0;
        else
            system_state <= {1'b0, argmax_valid, nn_valid, rms_valid};
    end

    // Status signals
    assign preprocessing_active = rms_valid;
    assign inference_active     = nn_valid;

endmodule


// ============================================================
// Neural Network Inference Engine
// Implements a simplified linear layer (dense layer) using
// INT8 weights. Takes 8 RMS features, outputs 8 class scores.
// The weights here are placeholders - in real deployment they
// are loaded from the trained model via weight_memory.v
// ============================================================
module nn_inference_engine #(
    parameter INPUT_CHANNELS = 8,
    parameter NUM_CLASSES    = 8
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    input  wire signed [7:0] feat_ch0, feat_ch1, feat_ch2, feat_ch3,
    input  wire signed [7:0] feat_ch4, feat_ch5, feat_ch6, feat_ch7,

    output reg signed [7:0] score0, score1, score2, score3,
    output reg signed [7:0] score4, score5, score6, score7,
    output reg valid
);

    // FSM states
    localparam IDLE    = 2'b00;
    localparam COMPUTE = 2'b01;
    localparam DONE    = 2'b10;

    reg [1:0] state;
    reg [7:0] compute_cycles;

    // Weight matrix (8 inputs x 8 outputs) - INT8
    // These would normally be loaded from BRAM (weight_memory.v)
    reg signed [7:0]  weights [0:NUM_CLASSES-1][0:INPUT_CHANNELS-1];
    reg signed [15:0] bias    [0:NUM_CLASSES-1];

    // Accumulators (wider to avoid overflow during MAC)
    reg signed [23:0] acc [0:NUM_CLASSES-1];

    // Captured feature values
    reg signed [7:0] features [0:INPUT_CHANNELS-1];

    integer i, j;

    // Load initial weights (placeholder values)
    initial begin
        for (i = 0; i < NUM_CLASSES; i = i + 1) begin
            for (j = 0; j < INPUT_CHANNELS; j = j + 1) begin
                weights[i][j] = 8'sd10;
            end
            bias[i] = 16'sd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            valid          <= 1'b0;
            compute_cycles <= 8'd0;
            score0 <= 0; score1 <= 0; score2 <= 0; score3 <= 0;
            score4 <= 0; score5 <= 0; score6 <= 0; score7 <= 0;
        end else begin
            case (state)
                IDLE: begin
                    valid <= 1'b0;
                    if (start) begin
                        // Capture input features
                        features[0] <= feat_ch0; features[1] <= feat_ch1;
                        features[2] <= feat_ch2; features[3] <= feat_ch3;
                        features[4] <= feat_ch4; features[5] <= feat_ch5;
                        features[6] <= feat_ch6; features[7] <= feat_ch7;
                        // Load biases into accumulators
                        for (i = 0; i < NUM_CLASSES; i = i + 1)
                            acc[i] <= {{8{bias[i][15]}}, bias[i]};
                        compute_cycles <= 8'd0;
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    // Multiply-accumulate: acc[class] += feature[i] * weight[class][i]
                    if (compute_cycles < INPUT_CHANNELS) begin
                        for (i = 0; i < NUM_CLASSES; i = i + 1)
                            acc[i] <= acc[i] + (features[compute_cycles] * weights[i][compute_cycles]);
                        compute_cycles <= compute_cycles + 8'd1;
                    end else begin
                        // Apply ReLU and output (take upper 8 bits of 24-bit accumulator)
                        score0 <= acc[0][23] ? 8'sd0 : acc[0][15:8];
                        score1 <= acc[1][23] ? 8'sd0 : acc[1][15:8];
                        score2 <= acc[2][23] ? 8'sd0 : acc[2][15:8];
                        score3 <= acc[3][23] ? 8'sd0 : acc[3][15:8];
                        score4 <= acc[4][23] ? 8'sd0 : acc[4][15:8];
                        score5 <= acc[5][23] ? 8'sd0 : acc[5][15:8];
                        score6 <= acc[6][23] ? 8'sd0 : acc[6][15:8];
                        score7 <= acc[7][23] ? 8'sd0 : acc[7][15:8];
                        state <= DONE;
                    end
                end

                DONE: begin
                    valid <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
