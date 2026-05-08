module top_nexys4 (
    input  logic        CLK100MHZ,
    input  logic        CPU_RESETN,
    input  logic        BTNC,         // Кнопка для анализа
    input  logic        BTNU,         // Кнопка СТАРТ
    output logic        UART_TXD_IN,
    output logic [15:0] LED
);

    // --- 1. Сигналы с атрибутами отладки ---
    // Эти сигналы Вивадо сама выведет в консоль Hardware Manager
    (* mark_debug = "true" *) logic btn_to_analyze;
    assign btn_to_analyze = BTNC;

    (* mark_debug = "true" *) logic [31:0] debug_r_data;
    (* mark_debug = "true" *) logic [5:0]  debug_r_addr;
    (* mark_debug = "true" *) logic [6:0]  debug_event_cnt;
    (* mark_debug = "true" *) logic        debug_busy;
    (* mark_debug = "true" *) logic        debug_done;
    (* mark_debug = "true" *) logic        debug_start_pulse;

    // --- 2. Сброс и запуск ---
    logic rst;
    assign rst = ~CPU_RESETN;

    logic [2:0] start_sync;
    always_ff @(posedge CLK100MHZ) start_sync <= {start_sync[1:0], BTNU};
    assign debug_start_pulse = start_sync[1] && !start_sync[2];

    // --- 3. Анализатор ---
    btn_analyzer #(.MEM_ADDR_W(6)) i_analyzer (
        .clk        (CLK100MHZ),
        .rst        (rst),
        .start      (debug_start_pulse),
        .tmw_limit  (32'd100_000_000), 
        .busy       (debug_busy),
        .done       (debug_done),
        .event_cnt  (debug_event_cnt),
        .r_addr     (debug_r_addr),
        .r_data     (debug_r_data),
        .btn_i      (btn_to_analyze)
    );

    // --- 4. UART FSM (она же работает как переборщик адресов для отладки) ---
    logic [7:0] tx_byte;
    logic       tx_start, tx_busy, tx_done;

    uart_tx i_uart_tx (
        .clk(CLK100MHZ), .rst(rst), .tx_byte(tx_byte),
        .tx_start(tx_start), .tx_busy(tx_busy), .tx_done(tx_done), .tx_pin(UART_TXD_IN)
    );

    typedef enum logic [2:0] {IDLE, READ_WAIT, SEND_B3, SEND_B2, SEND_B1, SEND_B0, NEXT} m_state_t;
    m_state_t state;

    always_ff @(posedge CLK100MHZ or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            debug_r_addr <= 0;
            tx_start <= 0;
        end else begin
            tx_start <= 0;
            case (state)
                IDLE: if (debug_done && debug_event_cnt > 0) begin 
                    state <= READ_WAIT; 
                    debug_r_addr <= 0; 
                end
                
                READ_WAIT: state <= SEND_B3; // Latency для BRAM

                SEND_B3: if (!tx_busy) begin tx_byte <= debug_r_data[31:24]; tx_start <= 1; state <= SEND_B2; end
                SEND_B2: if (tx_done)  begin tx_byte <= debug_r_data[23:16]; tx_start <= 1; state <= SEND_B1; end
                SEND_B1: if (tx_done)  begin tx_byte <= debug_r_data[15:8];  tx_start <= 1; state <= SEND_B0; end
                SEND_B0: if (tx_done)  begin tx_byte <= debug_r_data[7:0];   tx_start <= 1; state <= NEXT;    end

                NEXT: if (tx_done) begin
                    if ((debug_r_addr + 1) < debug_event_cnt) begin
                        debug_r_addr <= debug_r_addr + 1;
                        state <= READ_WAIT;
                    end else state <= IDLE;
                end
            endcase
        end
    end

    assign LED = {debug_busy, debug_done, debug_event_cnt[5:0], 8'b0};

endmodule