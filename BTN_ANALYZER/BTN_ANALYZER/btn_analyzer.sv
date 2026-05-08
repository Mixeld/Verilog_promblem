module btn_analyzer #(
    parameter int MEM_ADDR_W = 6
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic [31:0] tmw_limit,
    output logic        busy,
    output logic        done,
    output logic [MEM_ADDR_W:0] event_cnt,
    input  logic [MEM_ADDR_W-1:0] r_addr,
    output logic [31:0] r_data,
    input  logic        btn_i
);
    logic [2:0] btn_sync;
    always_ff @(posedge clk) btn_sync <= {btn_sync[1:0], btn_i};
    wire any_edge = btn_sync[1] ^ btn_sync[2];

    typedef enum {IDLE, MEASURE, FINISHED} state_t;
    state_t state;

    logic [31:0] timer, global_timer;
    logic [MEM_ADDR_W-1:0] w_addr;
    logic mem_w_en;

    assign busy = (state != IDLE);
    assign done = (state == FINISHED);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            event_cnt <= 0;
        end else begin
            mem_w_en <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    state <= MEASURE;
                    global_timer <= tmw_limit;
                    timer <= 0;
                    w_addr <= 0;
                    event_cnt <= 0;
                end
                MEASURE: begin
                    timer <= timer + 1;
                    if (global_timer > 0) global_timer <= global_timer - 1;
                    else state <= FINISHED;

                    if (any_edge) begin
                        mem_w_en <= 1'b1;
                        timer <= 0;
                        if (w_addr < (1<<MEM_ADDR_W)-1) w_addr <= w_addr + 1;
                        if (event_cnt < (1<<MEM_ADDR_W)) event_cnt <= event_cnt + 1;
                    end
                end
                FINISHED: if (!start) state <= IDLE;
            endcase
        end
    end

    simple_dpram #(.ADDR_W(MEM_ADDR_W)) mem_inst (
        .clk(clk), .w_addr(w_addr), .w_data(timer), .w_en(mem_w_en),
        .r_addr(r_addr), .r_data(r_data)
    );
endmodule