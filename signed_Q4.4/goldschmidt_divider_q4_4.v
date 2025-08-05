module goldschmidt_divider_q4_4 (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire signed [7:0] numerator,      // Q4.4 signed
    input wire signed [7:0] denominator,    // Q4.4 signed
    output reg signed [7:0] quotient,       // Q4.4 signed
    output reg valid,
    output reg error
);

    reg [4:0] count;
    reg [7:0] temp;

    localparam [3:0]
        IDLE              = 4'h0,
        VALIDATE_INPUT    = 4'h1,
        NORMALIZE_DENOM   = 4'h2,
        LOOKUP_INIT_APPROX= 4'h3,
        CONVERT           = 4'h4,
        FACTOR_CALC       = 4'hB,
        FIRST_MULT        = 4'h5,
        GOLDSCHMIDT_ITER  = 4'h6,
        APPLY_CORRECTION  = 4'h7,
        ROUND_RESULT      = 4'h8,
        OUTPUT_RESULT     = 4'h9,
        ERROR_STATE       = 4'hF;

    // Q-format constants
    localparam signed [15:0] Q8_8_ONE = 16'sh0100;
    localparam signed [15:0] Q8_8_TWO = 16'sh0200;
    localparam signed [7:0]  Q4_4_ONE = 8'sh10;
    localparam signed [7:0]  Q4_4_HALF = 8'sh08;
    localparam signed [7:0]  Q4_4_MAX = 8'sh7F;  // +127 in Q4.4
    localparam signed [7:0]  Q4_4_MIN = -8'sh80; // -128 in Q4.4
    localparam MAX_ITERATIONS = 3;

    reg [3:0] state, next_state;
    reg [2:0] iteration_counter;

    // Declare as signed for arithmetic correctness
    reg signed [15:0] num_q8_8;
    reg signed [15:0] denom_q8_8;
    reg signed [15:0] factor_q8_8;
    reg signed [31:0] mul_temp_32;

    reg signed [7:0] num_reg, denom_reg;
    reg signed [7:0] denom_norm_reg;
    reg [4:0] p;
    reg signed [5:0] shift;
    reg [7:0] factor_0;
    reg [2:0] index;

    reg result_sign;

    // Bit scan for normalization
    always @(*) begin
        if      (denom_reg[7]) p = 7;
        else if (denom_reg[6]) p = 6;
        else if (denom_reg[5]) p = 5;
        else if (denom_reg[4]) p = 4;
        else if (denom_reg[3]) p = 3;
        else if (denom_reg[2]) p = 2;
        else if (denom_reg[1]) p = 1;
        else if (denom_reg[0]) p = 0;
        else                   p = 0;

        shift = $signed(3 - p);
    end

    // Lookup table for initial approximation
    always @(*) begin
        case (index)
            3'd0: factor_0 = 8'd32;
            3'd1: factor_0 = 8'd28;
            3'd2: factor_0 = 8'd26;
            3'd3: factor_0 = 8'd23;
            3'd4: factor_0 = 8'd21;
            3'd5: factor_0 = 8'd20;
            3'd6: factor_0 = 8'd18;
            3'd7: factor_0 = 8'd17;
            default: factor_0 = 8'd0;
        endcase
    end

    // FSM: Next State
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (start) next_state = VALIDATE_INPUT;
            VALIDATE_INPUT: begin
                if (denom_reg == 0)
                    next_state = ERROR_STATE;
                else if (num_reg == 0 || denom_reg == Q4_4_ONE || num_reg == denom_reg)
                    next_state = OUTPUT_RESULT;
                else
                    next_state = NORMALIZE_DENOM;
            end
            NORMALIZE_DENOM:     next_state = LOOKUP_INIT_APPROX;
            LOOKUP_INIT_APPROX:  next_state = CONVERT;
            CONVERT:             next_state = FIRST_MULT;
            FIRST_MULT:          next_state = FACTOR_CALC;
            FACTOR_CALC:         next_state = GOLDSCHMIDT_ITER;
            GOLDSCHMIDT_ITER:    next_state = (iteration_counter >= MAX_ITERATIONS) ? APPLY_CORRECTION : FACTOR_CALC;
            APPLY_CORRECTION:    next_state = ROUND_RESULT;
            ROUND_RESULT:        next_state = OUTPUT_RESULT;
            OUTPUT_RESULT,
            ERROR_STATE:         next_state = IDLE;
            default:             next_state = IDLE;
        endcase
    end

    // FSM: Sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            valid <= 0;
            error <= 0;
            quotient <= 0;
            iteration_counter <= 0;
            num_reg <= 0;
            denom_reg <= 0;
            num_q8_8 <= 0;
            denom_q8_8 <= 0;
            factor_q8_8 <= 0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    valid <= 0;
                    error <= 0;
                    if (start) begin
                        result_sign <= numerator[7] ^ denominator[7];  // XOR: if signs differ, result is negative
                        num_reg <= (numerator[7]) ? -numerator : numerator;
                        denom_reg <= (denominator[7]) ? -denominator : denominator;
                        iteration_counter <= 0;
                    end
                end
                VALIDATE_INPUT: begin
                    if (num_reg == 0)
                        quotient <= 0;
                    else if (denom_reg == Q4_4_ONE)
                        quotient <= result_sign ? -num_reg : num_reg;
                    else if (num_reg == denom_reg)
                        quotient <= result_sign ? -Q4_4_ONE : Q4_4_ONE;
                end
                NORMALIZE_DENOM: begin
                    denom_norm_reg <= (shift >= 0) ? (denom_reg <<< shift) : (denom_reg >>> -shift);
                end
                LOOKUP_INIT_APPROX: begin
                    index <= denom_norm_reg[3:1];
                end
                CONVERT: begin
                    denom_q8_8 <= {denom_norm_reg, 4'b0};
                    num_q8_8   <= {num_reg, 4'b0};
                    factor_q8_8 <= factor_0 <<< 4;
                end
                FIRST_MULT: begin
                    mul_temp_32 = num_q8_8 * factor_q8_8;
                    num_q8_8    <= mul_temp_32[23:8];
                    mul_temp_32 = denom_q8_8 * factor_q8_8;
                    denom_q8_8  <= mul_temp_32[23:8];
                end
                FACTOR_CALC: begin
                    factor_q8_8 <= Q8_8_TWO - denom_q8_8;
                end
                GOLDSCHMIDT_ITER: begin
                    if (iteration_counter < MAX_ITERATIONS) begin
                        mul_temp_32 = num_q8_8 * factor_q8_8;
                        num_q8_8    <= mul_temp_32[23:8];
                        mul_temp_32 = denom_q8_8 * factor_q8_8;
                        denom_q8_8  <= mul_temp_32[23:8];
                        iteration_counter <= iteration_counter + 1;
                    end
                end
                APPLY_CORRECTION: begin
                    num_q8_8 <= (shift >= 0) ? (num_q8_8 <<< shift) : (num_q8_8 >>> -shift);
                end
                ROUND_RESULT: begin
                    // Round off
                    reg signed [7:0] rounded;
                    if (num_q8_8[3])
                        rounded = num_q8_8[11:4] + 1;
                    else
                        rounded = num_q8_8[11:4];

                    // Apply sign
                    quotient <= (result_sign) ? -rounded : rounded;

                    // Overflow clamp
                    if (quotient > Q4_4_MAX) quotient <= Q4_4_MAX;
                    else if (quotient < Q4_4_MIN) quotient <= Q4_4_MIN;
                end
                OUTPUT_RESULT: begin
                    valid <= 1;
                    error <= 0;
                end
                ERROR_STATE: begin
                    valid <= 1;
                    error <= 1;
                    quotient <= 0;
                end
            endcase
        end
    end

endmodule
