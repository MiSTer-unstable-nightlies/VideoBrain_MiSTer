module videobrain_video_clock (
    input wire clk, reset,
    input wire progressive,
    input wire locked, waitrequest,
    output wire ready,
    output wire write,
    output wire [5:0] address,
    output wire [31:0] writedata
);

localparam [31:0] NATIVE_K = 32'd2576980378;
localparam [31:0] PROGRESSIVE_K = 32'd2680059593;
localparam [5:0] FRACTION_REG = 7, APPLY_REG = 2;
localparam [2:0] IDLE = 0, WRITE_K = 1, START = 2, SETTLE = 3, WAIT_DONE = 4;
reg [2:0] state = IDLE;
reg request_meta = 0, request = 0, applied = 0, target = 0;

assign ready = !reset && state == IDLE && applied == request && locked && !waitrequest;
assign write = !reset && (state == WRITE_K || state == START);
assign address = state == WRITE_K ? FRACTION_REG : APPLY_REG;
assign writedata = state == WRITE_K ? (target ? PROGRESSIVE_K : NATIVE_K) : 32'd1;

always @(posedge clk) begin
    request_meta <= progressive;
    request <= request_meta;
    if (reset) begin
        state <= IDLE;
        request_meta <= 0;
        request <= 0;
        applied <= 0;
        target <= 0;
    end else begin
        case (state)
            IDLE: if (request != applied && locked && !waitrequest) begin
                target <= request;
                state <= WRITE_K;
            end
            WRITE_K: if (!waitrequest) state <= START;
            START: if (!waitrequest) state <= SETTLE;
            SETTLE: state <= WAIT_DONE;
            WAIT_DONE: if (!waitrequest && locked) begin
                applied <= target;
                state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule
