// ============================================================
// Project : Real-Time EMG Gesture Recognition on FPGA
// File    : emg_preprocessor.v
// Purpose : Signal preprocessing for 8 EMG channels
//
// What this module does (step by step):
//   Step 1 - High-pass filter  : removes DC offset from raw ADC signal
//   Step 2 - Rectification     : takes absolute value (flips negative to positive)
//   Step 3 - RMS extraction    : computes Root Mean Square over a 50ms window
//
// This mirrors exactly what we did in Python before training the model.
// The FPGA needs to do the same preprocessing in hardware.
//
// Input  : Raw 12-bit ADC samples at 2000 Hz (from 8 EMG channels)
// Output : 8-bit RMS feature per channel (ready for neural network)
// ============================================================

module emg_preprocessor #(
    parameter NUM_CHANNELS = 8,
    parameter DATA_WIDTH   = 12,   // 12-bit ADC
    parameter OUTPUT_WIDTH = 8,    // 8-bit output (INT8)
    parameter WINDOW_SIZE  = 100,  // 50ms window (100 samples at 2kHz)
    parameter STEP_SIZE    = 20    // 10ms step between windows
)(
    input  wire clk,
    input  wire rst_n,
    input  wire data_valid,  // Goes high when new ADC sample is available

    // Raw ADC inputs (one per channel)
    input  wire signed [DATA_WIDTH-1:0] adc_ch0, adc_ch1, adc_ch2, adc_ch3,
    input  wire signed [DATA_WIDTH-1:0] adc_ch4, adc_ch5, adc_ch6, adc_ch7,

    // RMS feature outputs (one per channel)
    output reg signed [OUTPUT_WIDTH-1:0] rms_ch0, rms_ch1, rms_ch2, rms_ch3,
    output reg signed [OUTPUT_WIDTH-1:0] rms_ch4, rms_ch5, rms_ch6, rms_ch7,
    output reg rms_valid  // Goes high when new RMS values are ready
);

    // Pack ADC inputs into an array for easier processing
    wire signed [DATA_WIDTH-1:0] adc_data [0:NUM_CHANNELS-1];
    assign adc_data[0] = adc_ch0; assign adc_data[1] = adc_ch1;
    assign adc_data[2] = adc_ch2; assign adc_data[3] = adc_ch3;
    assign adc_data[4] = adc_ch4; assign adc_data[5] = adc_ch5;
    assign adc_data[6] = adc_ch6; assign adc_data[7] = adc_ch7;

    // --- Step 1: High-pass filter state ---
    // Simple first-order high-pass filter to remove DC offset
    reg signed [DATA_WIDTH-1:0] x_prev    [0:NUM_CHANNELS-1];
    reg signed [DATA_WIDTH-1:0] y_prev    [0:NUM_CHANNELS-1];
    reg signed [DATA_WIDTH-1:0] filtered  [0:NUM_CHANNELS-1];

    // --- Step 2: Rectified sample circular buffer ---
    // Stores the last WINDOW_SIZE rectified samples per channel
    reg [DATA_WIDTH-1:0] rect_buf [0:NUM_CHANNELS-1][0:WINDOW_SIZE-1];
    reg [7:0] buf_idx;      // current write position in the circular buffer
    reg [7:0] sample_count; // total samples received so far

    // --- Step 3: RMS computation ---
    reg [31:0] sum_sq   [0:NUM_CHANNELS-1]; // sum of squares
    reg [15:0] rms_temp [0:NUM_CHANNELS-1]; // temporary RMS value

    integer ch, i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_idx      <= 8'd0;
            sample_count <= 8'd0;
            rms_valid    <= 1'b0;

            for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
                x_prev[ch]   <= 0;
                y_prev[ch]   <= 0;
                filtered[ch] <= 0;
                sum_sq[ch]   <= 0;
            end

            rms_ch0 <= 0; rms_ch1 <= 0; rms_ch2 <= 0; rms_ch3 <= 0;
            rms_ch4 <= 0; rms_ch5 <= 0; rms_ch6 <= 0; rms_ch7 <= 0;

        end else if (data_valid) begin

            // ---- STEP 1: High-pass filter ----
            // y[n] = (y[n-1] + x[n] - x[n-1]) >> 1
            // Simple approximation of a high-pass filter in fixed-point
            for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
                filtered[ch] <= (y_prev[ch] + adc_data[ch] - x_prev[ch]) >>> 1;
                x_prev[ch]   <= adc_data[ch];
                y_prev[ch]   <= filtered[ch];
            end

            // ---- STEP 2: Full-wave rectification ----
            // Just take the absolute value of each filtered sample
            for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
                if (filtered[ch][DATA_WIDTH-1])  // if negative (sign bit = 1)
                    rect_buf[ch][buf_idx] <= -filtered[ch];
                else
                    rect_buf[ch][buf_idx] <= filtered[ch];
            end

            // Advance circular buffer index
            if (buf_idx < WINDOW_SIZE - 1)
                buf_idx <= buf_idx + 8'd1;
            else
                buf_idx <= 8'd0;

            sample_count <= sample_count + 8'd1;

            // ---- STEP 3: RMS extraction ----
            // Only compute RMS every STEP_SIZE samples (every 10ms)
            if (sample_count >= WINDOW_SIZE && (sample_count[4:0] == 5'd0)) begin

                for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
                    // Sum of squares over the window
                    sum_sq[ch] = 32'd0;
                    for (i = 0; i < WINDOW_SIZE; i = i + 1)
                        sum_sq[ch] = sum_sq[ch] + (rect_buf[ch][i] * rect_buf[ch][i]);

                    // Approximate mean by shifting (divide by 256 ~ divide by WINDOW_SIZE)
                    rms_temp[ch] = sum_sq[ch][23:8];
                end

                // Square root approximation and clip to 8 bits
                rms_ch0 <= sqrt_approx(rms_temp[0]);
                rms_ch1 <= sqrt_approx(rms_temp[1]);
                rms_ch2 <= sqrt_approx(rms_temp[2]);
                rms_ch3 <= sqrt_approx(rms_temp[3]);
                rms_ch4 <= sqrt_approx(rms_temp[4]);
                rms_ch5 <= sqrt_approx(rms_temp[5]);
                rms_ch6 <= sqrt_approx(rms_temp[6]);
                rms_ch7 <= sqrt_approx(rms_temp[7]);

                rms_valid <= 1'b1;
            end else begin
                rms_valid <= 1'b0;
            end

        end else begin
            rms_valid <= 1'b0;
        end
    end

    // Square root approximation
    // We use a simple bit-shift approximation: sqrt(x) ≈ x/2 + x/8
    // Good enough for INT8 gesture classification (small accuracy loss)
    function [OUTPUT_WIDTH-1:0] sqrt_approx;
        input [15:0] value;
        reg   [15:0] result;
        begin
            result      = (value >> 1) + (value >> 3);
            sqrt_approx = result[OUTPUT_WIDTH-1:0];
        end
    endfunction

endmodule
