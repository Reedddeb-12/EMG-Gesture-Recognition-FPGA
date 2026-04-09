// ============================================================
// Project : Real-Time EMG Gesture Recognition on FPGA
// File    : dense_layer.v
// Purpose : Fully connected (Dense) layer hardware implementation
//
// In our CNN model we have two dense (fully connected) layers:
//   Dense Layer 1: 1472 inputs -> 128 neurons + ReLU
//   Dense Layer 2: 128  inputs -> 8  neurons  (final scores)
//
// A dense layer computes: output[j] = ReLU( sum_i(input[i] * weight[j][i]) + bias[j] )
//
// To speed things up, we use NUM_MAC_UNITS parallel MAC units
// so we can process multiple inputs at the same time.
// ============================================================

module dense_layer #(
    parameter INPUT_SIZE    = 128,
    parameter OUTPUT_SIZE   = 64,
    parameter DATA_WIDTH    = 8,
    parameter ACCUM_WIDTH   = 32,
    parameter NUM_MAC_UNITS = 16  // How many MACs run in parallel
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    input  wire signed [DATA_WIDTH-1:0] data_in  [0:INPUT_SIZE-1],
    output reg  signed [DATA_WIDTH-1:0] data_out [0:OUTPUT_SIZE-1],
    output reg  valid,
    output reg  done
);

    // FSM states
    localparam IDLE     = 2'b00;
    localparam COMPUTE  = 2'b01;
    localparam ACTIVATE = 2'b10;
    localparam DONE_ST  = 2'b11;

    reg [1:0]  state;
    reg [15:0] neuron_idx; // which output neuron we are computing
    reg [15:0] input_idx;  // which group of inputs we are processing

    // Weights and biases (loaded from BRAM in real deployment)
    reg signed [DATA_WIDTH-1:0]  weights     [0:OUTPUT_SIZE-1][0:INPUT_SIZE-1];
    reg signed [ACCUM_WIDTH-1:0] bias        [0:OUTPUT_SIZE-1];
    reg signed [ACCUM_WIDTH-1:0] accumulator [0:OUTPUT_SIZE-1];

    // Parallel MAC units
    wire signed [ACCUM_WIDTH-1:0] mac_result [0:NUM_MAC_UNITS-1];
    wire mac_enable;
    wire mac_clear;

    genvar i;
    generate
        for (i = 0; i < NUM_MAC_UNITS; i = i + 1) begin : mac_array
            mac_unit #(
                .INPUT_WIDTH  (DATA_WIDTH),
                .WEIGHT_WIDTH (DATA_WIDTH),
                .ACCUM_WIDTH  (ACCUM_WIDTH)
            ) mac_inst (
                .clk         (clk),
                .rst_n       (rst_n),
                .enable      (mac_enable),
                .clear_accum (mac_clear),
                .data_in     (data_in[input_idx + i]),
                .weight_in   (weights[neuron_idx][input_idx + i]),
                .accum_out   (mac_result[i]),
                .valid       ()
            );
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            neuron_idx <= 0;
            input_idx  <= 0;
            valid      <= 0;
            done       <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state      <= COMPUTE;
                        neuron_idx <= 0;
                        input_idx  <= 0;
                        valid      <= 0;
                        done       <= 0;
                        // Pre-load bias into accumulators
                        for (integer j = 0; j < OUTPUT_SIZE; j = j + 1)
                            accumulator[j] <= bias[j];
                    end
                end

                COMPUTE: begin
                    if (input_idx < INPUT_SIZE) begin
                        // Process NUM_MAC_UNITS inputs at once
                        input_idx <= input_idx + NUM_MAC_UNITS;
                        for (integer j = 0; j < NUM_MAC_UNITS; j = j + 1) begin
                            if (input_idx + j < INPUT_SIZE)
                                accumulator[neuron_idx] <= accumulator[neuron_idx] + mac_result[j];
                        end
                    end else begin
                        // Move to next output neuron
                        if (neuron_idx < OUTPUT_SIZE - 1) begin
                            neuron_idx <= neuron_idx + 1;
                            input_idx  <= 0;
                        end else begin
                            state <= ACTIVATE;
                        end
                    end
                end

                ACTIVATE: begin
                    // Apply ReLU: output = max(0, accumulator)
                    for (integer j = 0; j < OUTPUT_SIZE; j = j + 1) begin
                        if (accumulator[j] > 0)
                            data_out[j] <= accumulator[j][DATA_WIDTH-1:0];
                        else
                            data_out[j] <= 0;
                    end
                    state <= DONE_ST;
                    valid <= 1;
                end

                DONE_ST: begin
                    done  <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

    assign mac_enable = (state == COMPUTE);
    assign mac_clear  = (state == IDLE && start);

endmodule
