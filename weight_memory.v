// ============================================================
// Project : Real-Time EMG Gesture Recognition on FPGA
// File    : weight_memory.v
// Purpose : Stores trained CNN weights in FPGA Block RAM (BRAM)
//
// After training our model in Python, we exported the weights
// as an INT8 hex file (weights_real_data_init.mem).
// This module loads that file into the FPGA's Block RAM at startup.
//
// Total weights stored: ~200 KB
//   - Conv1D layer 1 weights:  1.5 KB
//   - Conv1D layer 2 weights:  6   KB
//   - Dense layer 1 weights:   184 KB
//   - Dense layer 2 weights:   1   KB
//
// The (* ram_style = "block" *) attribute tells Vivado to use
// dedicated BRAM blocks instead of LUT RAM (more efficient).
// ============================================================

module weight_memory #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter MEM_DEPTH  = 65536,
    parameter INIT_FILE  = "weights_real_data_init.mem"
)(
    input  wire clk,
    input  wire rst_n,
    input  wire read_enable,
    input  wire [ADDR_WIDTH-1:0] read_addr,
    output reg signed [DATA_WIDTH-1:0] read_data,
    output reg read_valid
);

    // BRAM - Vivado will infer Block RAM from this style
    (* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] weight_mem [0:MEM_DEPTH-1];

    // Load weights from file at startup (simulation + synthesis)
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, weight_mem);
        end else begin
            integer idx;
            for (idx = 0; idx < MEM_DEPTH; idx = idx + 1)
                weight_mem[idx] = 0;
        end
    end

    // Single-cycle read (synchronous BRAM read)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data  <= 0;
            read_valid <= 0;
        end else begin
            if (read_enable) begin
                read_data  <= weight_mem[read_addr];
                read_valid <= 1;
            end else begin
                read_valid <= 0;
            end
        end
    end

endmodule


// ============================================================
// Weight Memory Controller
// Manages which layer is reading weights and at what address.
// Each layer has its own base address in the weight memory:
//   Layer 0 (Conv1D-1)  starts at address 0x0000
//   Layer 1 (Conv1D-2)  starts at address 0x0500
//   Layer 2 (Dense-1)   starts at address 0x2000
//   Layer 3 (Dense-2)   starts at address 0x6000
// ============================================================
module weight_memory_controller #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,

    // Request interface (from each layer)
    input  wire        layer_request,
    input  wire [3:0]  layer_id,
    input  wire [ADDR_WIDTH-1:0] weight_offset,
    input  wire [15:0] weight_count,

    // Memory interface
    output reg        mem_read_enable,
    output reg [ADDR_WIDTH-1:0] mem_read_addr,
    input  wire signed [DATA_WIDTH-1:0] mem_read_data,
    input  wire       mem_read_valid,

    // Output to requesting layer
    output reg signed [DATA_WIDTH-1:0] weight_out,
    output reg        weight_valid,
    output reg        fetch_done
);

    // Base addresses for each layer's weights
    localparam [ADDR_WIDTH-1:0] CONV1_BASE  = 16'h0000;
    localparam [ADDR_WIDTH-1:0] CONV2_BASE  = 16'h0500;
    localparam [ADDR_WIDTH-1:0] DENSE1_BASE = 16'h2000;
    localparam [ADDR_WIDTH-1:0] DENSE2_BASE = 16'h6000;
    localparam [ADDR_WIDTH-1:0] DENSE3_BASE = 16'h8000;

    // FSM states
    localparam IDLE  = 2'b00;
    localparam FETCH = 2'b01;
    localparam WAIT  = 2'b10;

    reg [1:0]  state;
    reg [ADDR_WIDTH-1:0] base_addr;
    reg [15:0] fetch_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            mem_read_enable <= 0;
            mem_read_addr   <= 0;
            weight_valid    <= 0;
            fetch_done      <= 0;
            fetch_count     <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (layer_request) begin
                        // Choose which base address to start from
                        case (layer_id)
                            4'd0: base_addr <= CONV1_BASE;
                            4'd1: base_addr <= CONV2_BASE;
                            4'd2: base_addr <= DENSE1_BASE;
                            4'd3: base_addr <= DENSE2_BASE;
                            4'd4: base_addr <= DENSE3_BASE;
                            default: base_addr <= 0;
                        endcase
                        state       <= FETCH;
                        fetch_count <= 0;
                        fetch_done  <= 0;
                    end
                end

                FETCH: begin
                    if (fetch_count < weight_count) begin
                        mem_read_enable <= 1;
                        mem_read_addr   <= base_addr + weight_offset + fetch_count;
                        state           <= WAIT;
                    end else begin
                        fetch_done <= 1;
                        state      <= IDLE;
                    end
                end

                WAIT: begin
                    mem_read_enable <= 0;
                    if (mem_read_valid) begin
                        weight_out  <= mem_read_data;
                        weight_valid <= 1;
                        fetch_count <= fetch_count + 1;
                        state       <= FETCH;
                    end
                end
            endcase
        end
    end

endmodule
