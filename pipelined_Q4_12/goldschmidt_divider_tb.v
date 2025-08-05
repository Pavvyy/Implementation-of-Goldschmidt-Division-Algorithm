module goldschmidt_divider_tb;
    reg clk, rst_n, start;
    reg [15:0] numerator, denominator;
    wire [15:0] quotient;
    wire valid, error;
    
    always #5 clk = ~clk;
    
    goldschmidt_divider dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .numerator(numerator),
        .denominator(denominator),
        .quotient(quotient),
        .valid(valid),
        .error(error)
    );
    
    initial begin
        clk = 0;
        rst_n = 0;
        start = 0;
        numerator = 0;
        denominator = 0;
      
        #20 rst_n = 1;
        
        // Test case 1: 2.0 / 1.0 = 2.0
        #10; 
        numerator = 16'h2000;    // 2.0 in Q4.12
        denominator = 16'h1000;  // 1.0 in Q4.12
		  start = 1;
        #10 start = 0;
 
        // Wait for completion
        wait(valid);
		  if (error)
                $display("Test 1: ERROR - Division by zero");
        else
                $display("Test 1: 2.0/1.0 = %h (expected: 2000)", quotient);
        
		 
        // Test case 2: 1.0 / 2.0 = 0.5
        #20;
        numerator = 16'h1000;    // 1.0 in Q4.12
        denominator = 16'h2000;  // 2.0 in Q4.12
		  start = 1;
        #10 start = 0;
        
        wait(valid);
		  if (error)
                $display("Test 2: ERROR - Division by zero");
        else
                $display("Test 2: 1.0/2.0 = %h (expected: 0800)", quotient);
					 
		  #20;
        numerator = 16'h2000;    // 2.0 in Q4.12
        denominator = 16'h2000;  // 2.0 in Q4.12
		  start = 1;
        #10 start = 0;
        
        wait(valid);
		  if (error)
                $display("Test 3: ERROR - Division by zero");
        else
                $display("Test 3: 2.0/2.0 = %h (expected: 1000)", quotient);
					 
		  #20;
        numerator = 16'h2000;    // 2.0 in Q4.12
        denominator = 16'h0000;  // 0.0 in Q4.12
		  start = 1;
        #10 start = 0;
        
        wait(valid);
		  if (error)
                $display("Test 4: ERROR - Division by zero");
        else
                $display("Test 4: 2.0/0.0 = %h (expected: error)", quotient);
		  #20;
        numerator = 16'h2000;    // 2.0 in Q4.12
        denominator = 16'h7000;  // 7.0 in Q4.12
		  start = 1;
        #10 start = 0;
        
        wait(valid);
		  if (error)
                $display("Test 5: ERROR - Division by zero");
        else
                $display("Test 5: 2.0/7.0 = %h (expected: 0492)", quotient);
		  #20;
        numerator = 16'h2C00;    // 2.75 in Q4.12
        denominator = 16'h1400;  // 1.25 in Q4.12
		  start = 1;
        #10 start = 0;
        
        wait(valid);
		  if (error)
                $display("Test 6: ERROR - Division by zero");
        else
                $display("Test 6: 2.75/1.25 = %h (expected: 2333)", quotient);
        
        
        #100 $finish;
    end
    
    
    
endmodule
