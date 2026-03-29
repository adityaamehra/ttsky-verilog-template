`default_nettype none

module tt_um_adityaamehra (
    input  wire [7:0] ui_in,    // Dedicated inputs  — d_in[7:0]
    output wire [7:0] uo_out,   // Dedicated outputs — d_out[7:0]
    input  wire [7:0] uio_in,   // IOs: Input path   — uio_in[0] = valid_in
    output wire [7:0] uio_out,  // IOs: Output path  — uio_out[0] = valid_out
    output wire [7:0] uio_oe,   // IOs: Enable path  — bit0=1 (output), rest=0 (input)
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

// ── Parameters (Option A: 8-bit in/out) ──────────────────────────────────────
localparam integer in_width           = 8;
localparam integer out_width          = 8;
localparam integer decimation_ratio   = 8;
localparam integer order              = 6;
localparam integer differential_delay = 4;

// ── Internal signal mapping ───────────────────────────────────────────────────
wire signed [in_width-1:0]  d_in     = $signed(ui_in);
wire                         valid_in = uio_in[0];
wire signed [out_width-1:0] d_out;
wire                         valid_out;

assign uo_out  = d_out;
assign uio_out = {7'b0, valid_out};
assign uio_oe  = 8'b0000_0001;

wire _unused = &{ena, uio_in[7:1], 1'b0};

// ── CIC internals ─────────────────────────────────────────────────────────────
localparam integer COUNTW    = $clog2(decimation_ratio);
localparam integer GAIN_BITS = order * $clog2(decimation_ratio * differential_delay);

reg signed [in_width+GAIN_BITS-1:0] d_tmp;
reg signed [in_width+GAIN_BITS-1:0] integrator [0:order-1];
reg [COUNTW-1:0] counter;

// ── Counter ───────────────────────────────────────────────────────────────────
always @(negedge clk or negedge rst_n) begin
    if (!rst_n) counter <= {COUNTW{1'b1}};
    else if (valid_in)
        counter <= counter + 1;
end

// FIX 2: use COUNTW-wide zero for comparison
assign valid_out = (counter == {COUNTW{1'b0}});

/* verilator lint_off UNOPTFLAT */
wire signed [in_width+GAIN_BITS-1:0] comb   [0:order-1];
/* verilator lint_on UNOPTFLAT */
reg  signed [in_width+GAIN_BITS-1:0] d_comb [0:order-1][0:differential_delay-1];

integer i;
integer j;

// ── Integrator + decimation ───────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= order-1; i = i + 1)
            // FIX 1a: was (in_width+GAIN_BITS-1), now (in_width+GAIN_BITS)
            integrator[i] <= {(in_width+GAIN_BITS){1'b0}};
        // FIX 1b: was (in_width+GAIN_BITS-1), now (in_width+GAIN_BITS)
        d_tmp <= {(in_width+GAIN_BITS){1'b0}};
    end else if (valid_in) begin
        integrator[0] <= integrator[0] + {{GAIN_BITS{d_in[in_width-1]}}, d_in};
        for (i = 1; i <= order-1; i = i + 1)
            integrator[i] <= integrator[i] + integrator[i-1];
        if (valid_out)
            d_tmp <= integrator[order-1];
    end
end

// ── Comb section ──────────────────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= order-1; i = i + 1)
            for (j = 0; j < differential_delay; j = j + 1)
                // FIX 1c: was (in_width+GAIN_BITS-1), now (in_width+GAIN_BITS)
                d_comb[i][j] <= {(in_width+GAIN_BITS){1'b0}};
    end else begin
        if (valid_out) begin
            for (j = differential_delay-1; j > 0; j = j - 1)
                d_comb[0][j] <= d_comb[0][j-1];
            d_comb[0][0] <= d_tmp;
            for (i = 1; i <= order-1; i = i + 1) begin
                for (j = differential_delay-1; j > 0; j = j - 1)
                    d_comb[i][j] <= d_comb[i][j-1];
                d_comb[i][0] <= comb[i-1];
            end
        end
    end
end

// ── Comb taps ─────────────────────────────────────────────────────────────────
genvar r;
assign comb[0] = d_tmp - d_comb[0][differential_delay-1];
generate
    for (r = 1; r < order; r = r + 1) begin : hello
        assign comb[r] = comb[r-1] - d_comb[r][differential_delay-1];
    end
endgenerate

// ── Output with rounding — FIX 3: suppress intentional truncation warning ─────
/* verilator lint_off WIDTHTRUNC */
assign d_out =
    ( comb[order-1] + (1 << (in_width+GAIN_BITS-out_width-1)) )
    >>> (in_width+GAIN_BITS-out_width);
/* verilator lint_on WIDTHTRUNC */

endmodule