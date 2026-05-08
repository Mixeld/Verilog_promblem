module top_nexys4 (
    input  logic CLK100MHZ,
    input  logic CPU_RESETN,
    input  logic BTNC, // Кнопка анализа
    input  logic BTNU, // Кнопка СТАРТ
    output logic UART_TXD_IN,
    output logic [15:0] LED
);
    logic rst = ~CPU_RESETN;
    
    // Синхронизация кнопки старт
    logic start_q, start_db;
    always_ff @(posedge CLK100MHZ) begin
        start_q <= BTNU;
        start_db <= start_q;
    end
    wire start_pulse = start_q && !start_db;

    logic [5:0]  r_addr;
    logic [31:0] r_data;
    logic [6:0]  event_cnt;
    logic busy, done;

    btn_analyzer #(.MEM_ADDR_W(6)) i_cpu (
        .clk(CLK100MHZ), .rst(rst), .start(start_pulse),
        .tmw_limit(32'd100_000_000), // 1 секунда
        .busy(busy), .done(done), .event_cnt(event_cnt),
        .r_addr(r_addr), .r_data(r_data), .btn_i(BTNC)
    );

    // UART Master FSM
    typedef enum {WAIT, READ, SEND_B0, SEND_B1, SEND_B2, SEND_B3, NEXT} u_state_t;
    u_state_t u_state;
    logic [7:0] tx_byte;
    logic tx_start, tx_busy, tx_done;

    uart_tx i_uart (
        .clk(CLK100MHZ), .rst(rst), .tx_byte(tx_byte),
        .tx_start(tx_start), .tx_busy(tx_busy), .tx_done(tx_done), .tx_pin(UART_TXD_IN)
    );

    always_ff @(posedge CLK100MHZ or posedge rst) begin
        if (rst) begin
            u_state <= WAIT;
            r_addr <= 0;
            tx_start <= 0;
        end else begin
            tx_start <= 0;
            case (u_state)
                WAIT: if (done) begin u_state <= READ; r_addr <= 0; end
                READ: begin u_state <= SEND_B3; end // Пауза на чтение из BRAM
                SEND_B3: if (!tx_busy) begin tx_byte <= r_data[31:24]; tx_start <= 1; u_state <= SEND_B2; end
                SEND_B2: if (tx_done)  begin tx_byte <= r_data[23:16]; tx_start <= 1; u_state <= SEND_B1; end
                SEND_B1: if (tx_done)  begin tx_byte <= r_data[15:8];  tx_start <= 1; u_state <= SEND_B0; end
                SEND_B0: if (tx_done)  begin tx_byte <= r_data[7:0];   tx_start <= 1; u_state <= NEXT;    end
                NEXT: if (tx_done) begin
                    if (r_addr < event_cnt[5:0] - 1) begin
                        r_addr <= r_addr + 1;
                        u_state <= READ;
                    end else u_state <= WAIT;
                end
            endcase
        end
    end

    assign LED = {8'b0, busy, done, event_cnt[5:0]};
endmodule