// ============================================================
// Testbench : tb_emg_top.v
// Purpose   : Behavioural simulation of EMG Gesture Recognition Top Module
//
// This testbench simulates 5 different gesture patterns by driving
// synthetic ADC inputs and observing the gesture_class output.
//
// Gestures tested:
//   0 - Rest       : all channels low
//   1 - Fist       : channels 0-3 dominant
//   2 - Open Hand  : channels 4-7 dominant
//   3 - Pinch      : channels 0,1 dominant
//   4 - Point      : channel 2 dominant
// ============================================================

`timescale 1ns / 1ps

module tb_emg_top;

    // Clock and reset
    reg clk;
    reg rst_n;

    // ADC inputs
    reg adc_data_valid;
    reg signed [11:0] adc_ch0, adc_ch1, adc_ch2, adc_ch3;
    reg signed [11:0] adc_ch4, adc_ch5, adc_ch6, adc_ch7;

    // Outputs
    wire [2:0]  gesture_class;
    wire        gesture_valid;
    wire        preprocessing_active;
    wire        inference_active;
    wire [15:0] latency_cycles;
    wire [3:0]  system_state;

    // Instantiate DUT
    emg_gesture_recognition_top #(
        .NUM_CHANNELS(8),
        .ADC_WIDTH(12),
        .NUM_CLASSES(8),
        .FEATURE_WIDTH(8)
    ) DUT (
        .clk                  (clk),
        .rst_n                (rst_n),
        .adc_data_valid       (adc_data_valid),
        .adc_ch0              (adc_ch0),
        .adc_ch1              (adc_ch1),
        .adc_ch2              (adc_ch2),
        .adc_ch3              (adc_ch3),
        .adc_ch4              (adc_ch4),
        .adc_ch5              (adc_ch5),
        .adc_ch6              (adc_ch6),
        .adc_ch7              (adc_ch7),
        .gesture_class        (gesture_class),
        .gesture_valid        (gesture_valid),
        .preprocessing_active (preprocessing_active),
        .inference_active     (inference_active),
        .latency_cycles       (latency_cycles),
        .system_state         (system_state)
    );

    // 50 MHz clock (period = 20 ns)
    initial clk = 0;
    always #10 clk = ~clk;

    // Task to drive EMG pattern for N cycles
    task drive_emg;
        input signed [11:0] ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
                adc_data_valid <= 1;
                adc_ch0 <= ch0 + $signed($random) % 12'd50;
                adc_ch1 <= ch1 + $signed($random) % 12'd50;
                adc_ch2 <= ch2 + $signed($random) % 12'd50;
                adc_ch3 <= ch3 + $signed($random) % 12'd50;
                adc_ch4 <= ch4 + $signed($random) % 12'd50;
                adc_ch5 <= ch5 + $signed($random) % 12'd50;
                adc_ch6 <= ch6 + $signed($random) % 12'd50;
                adc_ch7 <= ch7 + $signed($random) % 12'd50;
            end
            adc_data_valid <= 0;
        end
    endtask

    integer test_num;

    initial begin
        // Initialise signals
        rst_n          = 0;
        adc_data_valid = 0;
        adc_ch0 = 0; adc_ch1 = 0; adc_ch2 = 0; adc_ch3 = 0;
        adc_ch4 = 0; adc_ch5 = 0; adc_ch6 = 0; adc_ch7 = 0;

        // Apply reset for 5 cycles
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        $display("=== EMG Gesture Recognition Testbench ===");

        // --- Test 0: Rest (all channels low) ---
        $display("[%0t] Test 0: Rest gesture", $time);
        drive_emg(12'd100, 12'd80,  12'd90,  12'd70,
                  12'd60,  12'd50,  12'd55,  12'd65,  200);
        repeat(50) @(posedge clk);

        // --- Test 1: Fist (channels 0-3 dominant) ---
        $display("[%0t] Test 1: Fist gesture", $time);
        drive_emg(12'd900, 12'd850, 12'd880, 12'd820,
                  12'd100, 12'd80,  12'd90,  12'd70,  200);
        repeat(50) @(posedge clk);

        // --- Test 2: Open Hand (channels 4-7 dominant) ---
        $display("[%0t] Test 2: Open Hand gesture", $time);
        drive_emg(12'd80,  12'd90,  12'd70,  12'd60,
                  12'd950, 12'd900, 12'd870, 12'd920, 200);
        repeat(50) @(posedge clk);

        // --- Test 3: Pinch (channels 0,1 dominant) ---
        $display("[%0t] Test 3: Pinch gesture", $time);
        drive_emg(12'd1000, 12'd950, 12'd100, 12'd80,
                  12'd70,   12'd60,  12'd90,  12'd100, 200);
        repeat(50) @(posedge clk);

        // --- Test 4: Point (channel 2 dominant) ---
        $display("[%0t] Test 4: Point gesture", $time);
        drive_emg(12'd80,   12'd70,   12'd1100, 12'd90,
                  12'd60,   12'd50,   12'd80,   12'd70,  200);
        repeat(50) @(posedge clk);

        $display("=== Simulation complete ===");
        $finish;
    end

    // Monitor gesture output
    always @(posedge clk) begin
        if (gesture_valid) begin
            $display("[%0t] >>> Gesture detected: class=%0d | latency=%0d cycles",
                     $time, gesture_class, latency_cycles);
        end
    end

endmodule
