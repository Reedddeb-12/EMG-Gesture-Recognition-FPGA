// ============================================================
// Project : Real-Time EMG Gesture Recognition on FPGA
// File    : mac_unit.v
// Purpose : Multiply-Accumulate (MAC) unit for neural network
//
// This is the basic math building block of our neural network.
// Every dot product in every layer uses MAC operations:
//   accumulator = accumulator + (input * weight)
//
// We use INT8 (8-bit integer) for inputs and weights.
// The accumulator is 32-bit to avoid overflow.
//
// On Artix-7, this maps to a DSP48E1 block for efficiency.
// ============================================================

module mac_unit #(
    parameter INPUT_WIDTH  = 8,   // INT8 input
    parameter WEIGHT_WIDTH = 8,   // INT8 weight
    parameter ACCUM_WIDTH  = 32   // 32-bit accumulator (prevents overflow)
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,       // Do a MAC operation this cycle
    input  wire clear_accum,  // Reset accumulator to zero (start new dot product)
    input  wire signed [INPUT_WIDTH-1:0]  data_in,
    input  wire signed [WEIGHT_WIDTH-1:0] weight_in,
    output reg  signed [ACCUM_WIDTH-1:0]  accum_out,
    output wire valid
);

    reg signed [INPUT_WIDTH+WEIGHT_WIDTH-1:0] product;
    reg valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product    <= 0;
            accum_out  <= 0;
            valid_reg  <= 0;
        end else begin
            if (clear_accum) begin
                // Start a new dot product - reset accumulator
                accum_out <= 0;
                valid_reg <= 0;
            end else if (enable) begin
                // Multiply then accumulate
                product   <= data_in * weight_in;
                accum_out <= accum_out + product;
                valid_reg <= 1;
            end
        end
    end

    assign valid = valid_reg;

endmodule
