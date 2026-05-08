module BTN_ANALYZER #(
    parameter int MEM_ADDR_W = 6 // 64 записи
)(
    input  logic        clk,
    input  logic        rst,
    
    // Control interface
    input  logic        start,      // Импульс начала измерения
    input  logic [31:0] tmw_limit,  // Окно измерения
    output logic        busy,       // Модуль занят
    output logic        done,       // Результат готов
    
    // Status
    output logic [MEM_ADDR_W:0] event_cnt, // Сколько реально поймали фронтов
    
    // Read interface
    input  logic [MEM_ADDR_W:0] r_addr,    // Адрес (0-63: интервалы, 64: RE, 65: FE)
    output logic [31:0]         r_data,    // Данные
    
    // Input
    input  logic        btn_i       // Асинхронная кнопка
);

    // 1. Синхронизация входа (обязательно)
    logic btn_sync_0, btn_sync_1, btn_prev;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            {btn_sync_1, btn_sync_0} <= 2'b0;
            btn_prev <= 1'b0;
        end else begin
            {btn_sync_1, btn_sync_0} <= {btn_sync_0, btn_i};
            btn_prev <= btn_sync_1;
        end
    end

    wire re_detected = (btn_sync_1 && !btn_prev);
    wire fe_detected = (!btn_sync_1 && btn_prev);
    wire any_edge    = re_detected || fe_detected;

    // 2. State Machine
    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        MEASURE = 2'b01,
        FINISHED= 2'b10
    } state_t;

    state_t state;
    logic [31:0] timer;
    logic [31:0] global_timer;
    logic [31:0] re_count, fe_count;
    logic [MEM_ADDR_W-1:0] w_addr;
    logic mem_w_en;

    assign busy = (state != IDLE);
    assign done = (state == FINISHED);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            timer <= 0;
            global_timer <= 0;
            w_addr <= 0;
            re_count <= 0;
            fe_count <= 0;
            event_cnt <= 0;
            mem_w_en <= 1'b0;
        end else begin
            mem_w_en <= 1'b0; // Default

            case (state)
                IDLE: begin
                    if (start) begin
                        state <= MEASURE;
                        timer <= 0;
                        global_timer <= tmw_limit;
                        w_addr <= 0;
                        re_count <= 0;
                        fe_count <= 0;
                        event_cnt <= 0;
                    end
                end

                MEASURE: begin
                    timer <= timer + 1;
                    if (global_timer > 0) global_timer <= global_timer - 1;

                    if (any_edge) begin
                        // Сохраняем длительность интервала
                        mem_w_en <= 1'b1;
                        timer <= 0; // Сброс таймера интервала
                        
                        if (w_addr < (1 << MEM_ADDR_W) - 1)
                            w_addr <= w_addr + 1;
                        
                        if (event_cnt < (1 << MEM_ADDR_W))
                            event_cnt <= event_cnt + 1;

                        if (re_detected) re_count <= re_count + 1;
                        if (fe_detected) fe_count <= fe_count + 1;
                    end

                    // Выход по таймауту
                    if (global_timer == 0) begin
                        state <= FINISHED;
                    end
                end

                FINISHED: begin
                    if (!start) state <= IDLE; // Ждем снятия сигнала start для сброса
                end
            endcase
        end
    end

    // 3. Хранилище интервалов
    logic [31:0] mem_out;
    simple_dpram #(.ADDR_W(MEM_ADDR_W), .DATA_W(32)) interval_mem (
        .clk    (clk),
        .w_addr (w_addr),
        .w_data (timer),
        .w_en   (mem_w_en),
        .r_addr (r_addr[MEM_ADDR_W-1:0]),
        .r_data (mem_out)
    );

    // 4. Мультиплексор вывода (регистровый, чтобы не завалить тайминги)
    always_ff @(posedge clk) begin
        if (r_addr < (1 << MEM_ADDR_W))
            r_data <= mem_out;
        else if (r_addr == 7'd64)
            r_data <= re_count;
        else if (r_addr == 7'd65)
            r_data <= fe_count;
        else
            r_data <= 32'hDEADBEEF; // Удобно для дебага
    end

endmodule