`default_nettype none
`timescale 1ns / 1ps

/* Testbench for tt_um_example (CIC filter).
   Instantiates the module and exposes wires for cocotb test.py.

   Signal mapping:
     ui_in  [7:0]  — d_in  (8-bit signed input sample)
     uio_in [0]    — valid_in
     uo_out [7:0]  — d_out (8-bit signed decimated output)
     uio_out[0]    — valid_out
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;    // d_in[7:0]
  reg [7:0] uio_in;   // uio_in[0] = valid_in, [7:1] unused
  wire [7:0] uo_out;  // d_out[7:0]
  wire [7:0] uio_out; // uio_out[0] = valid_out
  wire [7:0] uio_oe;  // driven by DUT: 8'b0000_0001

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  tt_um_adityaamehra user_project (

`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

endmodule