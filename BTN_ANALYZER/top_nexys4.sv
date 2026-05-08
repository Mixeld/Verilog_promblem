// ============================================================================
// Top Module для Nexys 4 / Nexys 4 DDR
// Анализатор дребезга с выводом результатов через UART (115200 baud)
// ============================================================================

module top_nexys4 (
    input  logic        CLK100MHZ,    // Сигнал 100 МГц с пина E3
    input  logic        CPU_RESETN,   // Красная кнопка сброса (Active Low)
    input  logic        BTNC,         // Центральная кнопка - объект анализа
    input  logic        BTNU,         // Верхняя кнопка - СТАРТ измерения
    output logic        UART_TXD_IN,  // Линия передачи UART в сторону USB-UART чипа
    output logic [15:0] LED           // Светодиоды для индикации статуса
);

    // --- 1. Сброс и Синхронизация ---
    // На Nexys 4 кнопка CPU_RESETN выдает 0 при нажатии. Инвертируем.
    logic rst;
    assign rst = ~CPU_RESETN;

    // Синхронизатор для кнопки START (BTNU) во избежание метастабильности
    logic [2:0] start_sync;
    always_ff @(posedge CLK100MHZ or posedge rst) begin
        if (rst) start_sync <= 3'b0;
        else     start_sync <= {start_sync[1:0], BTNU};
    end
    // Детектор переднего фронта (одиночный импульс при нажатии)
    wire start_pulse = start_sync[1] && !start_sync[2];

    // --- 2. Экземпляр Анализатора ---
    logic [5:0]  r_addr;     // Адрес чтения (0..63)
    logic [31:0] r_data;     // Данные из памяти
    logic [6:0]  event_cnt;  // Количество реально записанных событий (0..64)
    logic        busy, done;

    btn_analyzer #(
        .MEM_ADDR_W(6)       // 2^6 = 64 записи
    ) i_analyzer (
        .clk        (CLK100MHZ),
        .rst        (rst),
        .start      (start_pulse),
        .tmw_limit  (32'd100_000_000), // Окно измерения - 1 секунда (при 100МГц)
        .busy       (busy),
        .done       (done),
        .event_cnt  (event_cnt),
        .r_addr     (r_addr),
        .r_data     (r_data),
        .btn_i      (BTNC)           // Анализируем центральную кнопку
    );

    // --- 3. Экземпляр UART Передатчика ---
    logic [7:0] tx_byte;
    logic       tx_start, tx_busy, tx_done;

    uart_tx #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) i_uart_tx (
        .clk      (CLK100MHZ),
        .rst      (rst),
        .tx_byte  (tx_byte),
        .tx_start (tx_start),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done),
        .tx_pin   (UART_TXD_IN)
    );

    // --- 4. Master FSM: Вычитывание данных и отправка в UART ---
    typedef enum logic [2:0] {
        IDLE,           // Ждем окончания измерения
        READ_INIT,      // Подготовка чтения из BRAM
        READ_WAIT,      // Такт задержки для BRAM (latency)
        SEND_BYTE_3,    // Отправка байтов 32-битного слова (MSB first)
        SEND_BYTE_2,
        SEND_BYTE_1,
        SEND_BYTE_0,
        NEXT_RECORD     // Переход к следующей записи
    } m_state_t;

    m_state_t state;

    always_ff @(posedge CLK100MHZ or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            r_addr <= 0;
            tx_start <= 1'b0;
            tx_byte <= 8'h00;
        end else begin
            tx_start <= 1'b0; // Импульсный сигнал

            case (state)
                IDLE: begin
                    if (done) begin
                        if (event_cnt > 0) begin
                            state <= READ_INIT;
                            r_addr <= 0;
                        end else begin
                            state <= IDLE; // Ничего не поймали - возвращаемся
                        end
                    end
                end

                READ_INIT: begin
                    state <= READ_WAIT; // Просто ждем один такт
                end

                READ_WAIT: begin
                    state <= SEND_BYTE_3;
                end

                // Отправляем 32-битное число побайтово
                SEND_BYTE_3: begin
                    if (!tx_busy) begin
                        tx_byte <= r_data[31:24];
                        tx_start <= 1'b1;
                        state <= SEND_BYTE_2;
                    end
                end

                SEND_BYTE_2: if (tx_done) begin tx_byte <= r_data[23:16]; tx_start <= 1'b1; state <= SEND_BYTE_1; end
                SEND_BYTE_1: if (tx_done) begin tx_byte <= r_data[15:8];  tx_start <= 1'b1; state <= SEND_BYTE_0; end
                SEND_BYTE_0: if (tx_done) begin tx_byte <= r_data[7:0];   tx_start <= 1'b1; state <= NEXT_RECORD; end

                NEXT_RECORD: begin
                    if (tx_done) begin
                        // Сравниваем индекс (r_addr) с количеством (event_cnt)
                        if ((r_addr + 1) < event_cnt) begin
                            r_addr <= r_addr + 1;
                            state <= READ_INIT; // Читаем следующее слово
                        end else begin
                            state <= IDLE; // Всё отправили
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign LED[15] = busy;
    assign LED[14] = done;
    assign LED[13:7] = 7'b0;
    assign LED[6:0] = event_cnt;

endmodule