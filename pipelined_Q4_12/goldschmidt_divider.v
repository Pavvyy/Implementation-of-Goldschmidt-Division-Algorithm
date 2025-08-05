
module goldschmidt_divider (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [15:0] numerator,      // Q4.12 format
    input wire [15:0] denominator,    // Q4.12 format
    output reg [15:0] quotient,       // Q4.12 format
    output reg valid,
    output reg error
);

reg [4:0] count;
reg [15:0]temp;

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

// Constants
localparam [31:0] Q8_24_ONE = 32'h01000000;  // 1.0 in Q8.24
localparam [31:0] Q8_24_TWO = 32'h02000000;  // 2.0 in Q8.24
localparam [15:0] Q4_12_ONE = 16'h1000;      // 1.0 in Q4.12
localparam [15:0] Q4_12_HALF = 16'h0800;     // 0.5 in Q4.12
localparam MAX_ITERATIONS = 3;

// State machine registers
reg [3:0] state, next_state;
reg [2:0] iteration_counter;

// Working registers (Q8.24 format for intermediate calculations)
reg [31:0] num_q8_24;        // Numerator in Q8.24
reg [31:0] denom_q8_24;      // Denominator in Q8.24
reg [31:0] factor_q8_24;     // Factor (2 - d*x) in Q8.24
reg [64:0] mul_temp_64;        // Temporary multiplication result

// Input capture registers
reg [15:0] num_reg, denom_reg;
reg[15:0] denom_norm_reg;
reg[4:0]p;// internal: position of MSB in Denom
reg signed[5:0] shift;
reg[15:0] factor_0;

// Pipelining
reg [1:0] fmult_count;
reg [1:0] iter_mult_count;

 always @(*) begin
    // Priority encoder to find index p of highest 1 in Di
    if      (denom_reg[15]) p = 15;
    else if (denom_reg[14]) p = 14;
    else if (denom_reg[13]) p = 13;
    else if (denom_reg[12]) p = 12;
    else if (denom_reg[11]) p = 11;
    else if (denom_reg[10]) p = 10;
    else if (denom_reg[9 ]) p = 9;
    else if (denom_reg[8 ]) p = 8;
    else if (denom_reg[7 ]) p = 7;
    else if (denom_reg[6 ]) p = 6;
    else if (denom_reg[5 ]) p = 5;
    else if (denom_reg[4 ]) p = 4;
    else if (denom_reg[3 ]) p = 3;
    else if (denom_reg[2 ]) p = 2;
    else if (denom_reg[1 ]) p = 1;
    else if (denom_reg[0 ]) p = 0;
    else              p = 0; 
	 
	 shift = $signed(11 - p);
    
	end

reg[2:0]index;

always @(*) begin
    case (index)
      3'd0: factor_0 = 16'd8192;  // 1/0.5000 = 2.0000
      3'd1: factor_0 = 16'd7282;  // 1/0.5625 = 1.7778
      3'd2: factor_0 = 16'd6554;  // 1/0.6250 = 1.6000
      3'd3: factor_0 = 16'd5958;  // 1/0.6875 = 1.4545
      3'd4: factor_0 = 16'd5461;  // 1/0.7500 = 1.3333
      3'd5: factor_0 = 16'd5041;  // 1/0.8125 = 1.2308
      3'd6: factor_0 = 16'd4681;  // 1/0.8750 = 1.1429	
      3'd7: factor_0 = 16'd4369;  // 1/0.9375 = 1.0667
      default: factor_0= 16'd0;
    endcase
  end

// State machine - combinational next state logic
always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (start) 
                next_state = VALIDATE_INPUT;
        end
        
        VALIDATE_INPUT: begin
            if (denom_reg == 16'h0000)  // Division by zero
                next_state = ERROR_STATE;
            else if (num_reg == 16'h0000)  // Zero numerator
                next_state = OUTPUT_RESULT;
				else if (denom_reg==16'h1000)   //Denominator one
						next_state= OUTPUT_RESULT;
				else if (num_reg==denom_reg)  // Numerator & Denominator equal
						next_state=OUTPUT_RESULT;
            else
                next_state = NORMALIZE_DENOM;
        end
        
        NORMALIZE_DENOM: begin
            next_state = LOOKUP_INIT_APPROX;
        end
        
        LOOKUP_INIT_APPROX: begin
            next_state = CONVERT;
        end
		  
        CONVERT: begin
        next_state = FIRST_MULT; 
		  end

		  FIRST_MULT: begin
            if (fmult_count == 2'd2)
					next_state = FACTOR_CALC;
				else
					next_state = FIRST_MULT;  // Stay in state until done
        end
		  
		  FACTOR_CALC: begin
				next_state = GOLDSCHMIDT_ITER;
		  end
		  
        GOLDSCHMIDT_ITER: begin
            if (iter_mult_count == 2'd2) begin
					if (iteration_counter == MAX_ITERATIONS - 1)
						next_state = APPLY_CORRECTION;
					else
						next_state = FACTOR_CALC;  // Go to FACTOR_CALC for next iteration
				end else begin
					next_state = GOLDSCHMIDT_ITER;  // Wait until all 3 pipeline steps done
				end
        end
        
        APPLY_CORRECTION: begin
            next_state = ROUND_RESULT;
        end
        
        ROUND_RESULT: begin
            next_state = OUTPUT_RESULT;
        end
        
        OUTPUT_RESULT: begin
            next_state = IDLE;
        end
        
        ERROR_STATE: begin
            next_state = IDLE;
        end
        
        default: next_state = IDLE;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        valid <= 1'b0;
        error <= 1'b0;
        quotient <= 16'h0000;
        iteration_counter <= 3'b000;
        num_reg <= 16'h0000;
        denom_reg <= 16'h0000;
        num_q8_24 <= 32'h00000000;
        denom_q8_24 <= 32'h00000000;
        factor_q8_24 <= 32'h00000000;
        mul_temp_64 <= 64'h00000000;
		  fmult_count <= 2'd0;
		  iter_mult_count <= 2'd0;
    end else begin
        state <= next_state;
        
        case (state)
            IDLE: begin
                valid <= 1'b0;
                error <= 1'b0;
                if (start) begin
                    num_reg <= numerator;
                    denom_reg <= denominator;
                    iteration_counter <= 3'b000;
						  fmult_count <= 2'd0;
						  iter_mult_count <= 2'd0;
                end
            end
            
            VALIDATE_INPUT: begin
                if (num_reg == 16'h0000) 
                    quotient <= 16'h0000;  
					else if (denom_reg==16'h1000) 
						  quotient <= num_reg;
					else if (num_reg==denom_reg)
							quotient<=16'h1000;
            end
            
            NORMALIZE_DENOM: begin
					
                if (shift >= 0) begin
							denom_norm_reg <= denom_reg << shift;
					end else begin
							denom_norm_reg <= denom_reg >> -shift;
							end
				end
            
            LOOKUP_INIT_APPROX: begin
				$display("Normalized denominator: %h",denom_norm_reg);
                // Extract index from normalized denominator
                // Use upper bits for lookup table index
                index <= denom_norm_reg[11:8] - 4'd8;
					 
            end
				
				CONVERT: begin
				
            denom_q8_24 <= {denom_norm_reg, 12'b0}; // Convert Q4.12 → Q8.24
            num_q8_24 <= {num_reg, 12'b0}; 
				factor_q8_24 <= factor_0 << 12;  
				$display("Initial reciprocal: %h",factor_0);
				end
				
				FIRST_MULT: begin
					case (fmult_count)
						2'd0: begin
							$display("FIRST_MULT Stage 1: num_q8_24 = %h, factor_q8_24 = %h", num_q8_24, factor_q8_24);
							mul_temp_64 <= num_q8_24 * factor_q8_24;
							fmult_count <= 2'd1;
						end

						2'd1: begin
							num_q8_24 <= mul_temp_64[55:24];
							$display("FIRST_MULT Stage 2: num_result = %h", mul_temp_64[55:24]);
							mul_temp_64 <= denom_q8_24 * factor_q8_24;
							fmult_count <= 2'd2;
						end
		
						2'd2: begin
							denom_q8_24 <= mul_temp_64[55:24];
							$display("FIRST_MULT Stage 3: denom_result = %h", mul_temp_64[55:24]);
							fmult_count <= 2'd0;
						end
					endcase
				end
				
				FACTOR_CALC: begin
					factor_q8_24 <= Q8_24_TWO - denom_q8_24;
				end
				
            GOLDSCHMIDT_ITER: begin
					 case (iter_mult_count)
						  2'd0: begin
								mul_temp_64 <= num_q8_24 * factor_q8_24;
								iter_mult_count <= 2'd1;
						  end
						  2'd1: begin
								num_q8_24 <= mul_temp_64[55:24];
								mul_temp_64 <= denom_q8_24 * factor_q8_24;
								iter_mult_count <= 2'd2;
						  end
						  2'd2: begin
								denom_q8_24 <= mul_temp_64[55:24];
								iter_mult_count <= 2'd0;
								iteration_counter <= iteration_counter + 1;

								$display("ITER%d: denom = %h, num = %h, factor = %h", iteration_counter, denom_q8_24, num_q8_24, factor_q8_24);
						  end
					 endcase
				end

            
            APPLY_CORRECTION: begin
                // Apply shift correction based on normalization
              if (shift>=0) begin
                    num_q8_24 <= num_q8_24 << (shift);
                end else begin
                    num_q8_24 <= num_q8_24 >> (-shift);
                end
            end
            
            ROUND_RESULT: begin
                // Round down Q8.24 to Q4.12 
                quotient <= num_q8_24[27:12]; 
					 $display("ROUND_RESULT: num_q8_24 = %h, quotient = %h", num_q8_24, num_q8_24[27:12]);
            end
            
            OUTPUT_RESULT: begin
                valid <= 1'b1;
                error <= 1'b0;
            end
            
            ERROR_STATE: begin
                valid <= 1'b1;
                error <= 1'b1;
                quotient <= 16'h0000;
            end
        endcase
    end
end

endmodule
