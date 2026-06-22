/*
 * Copyright (c) 2026 Detronyx contributors
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_detronyx_uart_trace_exerciser #(
    // Default: 50 MHz / 115200 baud - 1 = 433.027...
    parameter [8:0] BAUD_RELOAD = 9'd433
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  wire       uart_tx;
  wire [5:0] status;

  detronyx_uart_trace_exerciser_core #(
      .BAUD_RELOAD (BAUD_RELOAD)
  ) u_core (
      .clk_i       (clk),
      .rst_ni      (rst_n),
      .ce_i        (ena),
      .probe_i     (ui_in),
      .uart_rx_i   (uio_in[0]),
      .pattern_o   (uo_out),
      .uart_tx_o   (uart_tx),
      .status_o    (status)
  );

  assign uio_out = {status, uart_tx, 1'b0};
  assign uio_oe  = 8'b11111110;

  wire _unused_uio_in = &{1'b0, uio_in[7:1]};

endmodule

module detronyx_uart_trace_exerciser_core #(
    parameter [8:0] BAUD_RELOAD = 9'd433
) (
    input  wire       clk_i,
    input  wire       rst_ni,
    input  wire       ce_i,
    input  wire [7:0] probe_i,
    input  wire       uart_rx_i,
    output wire [7:0] pattern_o,
    output wire       uart_tx_o,
    output wire [5:0] status_o
);

  localparam [7:0] CMD_TRACE_MASK   = 8'h10;
  localparam [7:0] CMD_SAMPLE_DIV   = 8'h11;
  localparam [7:0] CMD_TRACE_CTRL   = 8'h12;
  localparam [7:0] CMD_PATTERN_MODE = 8'h20;
  localparam [7:0] CMD_PATTERN_DIV  = 8'h21;
  localparam [7:0] CMD_PATTERN_A    = 8'h22;
  localparam [7:0] CMD_STATUS       = 8'h30;
  localparam [7:0] CMD_PING         = 8'h31;

  localparam [7:0] PKT_TRACE  = 8'he1;
  localparam [7:0] PKT_STATUS = 8'ha5;
  localparam [7:0] PKT_PING   = 8'hd7;
  localparam [1:0] PKT_KIND_TRACE  = 2'd0;
  localparam [1:0] PKT_KIND_STATUS = 2'd1;
  localparam [1:0] PKT_KIND_PING   = 2'd2;

  wire [7:0] rx_byte;
  wire       rx_valid;
  wire       rx_frame_error;

  wire       tx_ready;
  wire       tx_busy;

  detronyx_uart_rx #(
      .BAUD_RELOAD (BAUD_RELOAD)
  ) u_uart_rx (
      .clk_i         (clk_i),
      .rst_ni        (rst_ni),
      .ce_i          (ce_i),
      .rx_i          (uart_rx_i),
      .data_o        (rx_byte),
      .valid_o       (rx_valid),
      .frame_error_o (rx_frame_error)
  );

  detronyx_uart_tx #(
      .BAUD_RELOAD (BAUD_RELOAD)
  ) u_uart_tx (
      .clk_i      (clk_i),
      .rst_ni     (rst_ni),
      .ce_i       (ce_i),
      .data_i     (pkt_byte_r),
      .valid_i    (pkt_active_q & tx_ready),
      .ready_o    (tx_ready),
      .tx_o       (uart_tx_o),
      .busy_o     (tx_busy)
  );

  reg [7:0] trace_mask_q;
  reg [3:0] sample_div_q;
  reg [3:0] sample_cnt_q;
  reg [7:0] last_sample_q;
  reg [7:0] delta_q;
  reg [7:0] event_count_q;
  reg [7:0] drop_count_q;
  reg       armed_q;
  reg       stream_q;
  reg       overflow_q;
  reg       rx_error_sticky_q;
  reg       event_toggle_q;

  reg       trace_pending_q;
  reg [7:0] trace_sample_q;
  reg [7:0] trace_delta_q;
  reg [7:0] trace_change_q;

  reg [2:0] pattern_mode_q;
  reg [5:0] pattern_div_q;
  reg [5:0] pattern_cnt_q;
  reg [7:0] pattern_a_q;
  reg [7:0] pattern_out_q;

  reg       wait_arg_q;
  reg [7:0] cmd_q;
  reg       status_pending_q;
  reg       ping_pending_q;

  reg       pkt_active_q;
  reg [1:0] pkt_kind_q;
  reg [1:0] pkt_index_q;
  reg [7:0] pkt_byte_r;

  wire       sample_tick = sample_cnt_q == 4'h0;
  wire [7:0] change_mask = (probe_i ^ last_sample_q) & trace_mask_q;
  wire       trace_event = armed_q & stream_q & sample_tick & (|change_mask);
  wire       pattern_tick = pattern_cnt_q == 6'h00;
  wire       busy_any = tx_busy | pkt_active_q | trace_pending_q |
                        status_pending_q | ping_pending_q;
  wire [7:0] status_byte = {overflow_q, rx_error_sticky_q, trace_pending_q,
                            stream_q, armed_q, pattern_mode_q};

  always @* begin
    case (pkt_kind_q)
      PKT_KIND_STATUS: begin
        case (pkt_index_q)
          2'd0:    pkt_byte_r = PKT_STATUS;
          2'd1:    pkt_byte_r = status_byte;
          2'd2:    pkt_byte_r = event_count_q;
          default: pkt_byte_r = drop_count_q;
        endcase
      end
      PKT_KIND_PING: begin
        case (pkt_index_q)
          2'd0:    pkt_byte_r = PKT_PING;
          2'd1:    pkt_byte_r = 8'h54;
          2'd2:    pkt_byte_r = 8'h01;
          default: pkt_byte_r = status_byte;
        endcase
      end
      default: begin
        case (pkt_index_q)
          2'd0:    pkt_byte_r = PKT_TRACE;
          2'd1:    pkt_byte_r = trace_sample_q;
          2'd2:    pkt_byte_r = trace_delta_q;
          default: pkt_byte_r = trace_change_q;
        endcase
      end
    endcase
  end

  assign pattern_o = pattern_out_q;
  assign status_o = {event_toggle_q, rx_error_sticky_q, overflow_q,
                     busy_any, stream_q, armed_q};

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trace_mask_q <= 8'hff;
      sample_div_q <= 4'h0;
      sample_cnt_q <= 4'h0;
      last_sample_q <= 8'h00;
      delta_q <= 8'h00;
      event_count_q <= 8'h00;
      drop_count_q <= 8'h00;
      armed_q <= 1'b0;
      stream_q <= 1'b0;
      overflow_q <= 1'b0;
      rx_error_sticky_q <= 1'b0;
      event_toggle_q <= 1'b0;

      trace_pending_q <= 1'b0;
      trace_sample_q <= 8'h00;
      trace_delta_q <= 8'h00;
      trace_change_q <= 8'h00;

      pattern_mode_q <= 3'd1;
      pattern_div_q <= 6'd15;
      pattern_cnt_q <= 6'h00;
      pattern_a_q <= 8'h55;
      pattern_out_q <= 8'h00;

      wait_arg_q <= 1'b0;
      cmd_q <= 8'h00;
      status_pending_q <= 1'b0;
      ping_pending_q <= 1'b0;

      pkt_active_q <= 1'b0;
      pkt_kind_q <= PKT_KIND_TRACE;
      pkt_index_q <= 2'd0;

    end else if (ce_i) begin
      if (rx_frame_error) begin
        rx_error_sticky_q <= 1'b1;
      end

      if (rx_valid) begin
        if (wait_arg_q) begin
          wait_arg_q <= 1'b0;
          case (cmd_q)
            CMD_TRACE_MASK: begin
              trace_mask_q <= rx_byte;
            end
            CMD_SAMPLE_DIV: begin
              sample_div_q <= rx_byte[3:0];
            end
            CMD_TRACE_CTRL: begin
              armed_q <= rx_byte[0];
              stream_q <= rx_byte[1];
              if (rx_byte[0] && !armed_q) begin
                last_sample_q <= probe_i;
                delta_q <= 8'h00;
                sample_cnt_q <= sample_div_q;
              end
              if (rx_byte[2]) begin
                event_count_q <= 8'h00;
                drop_count_q <= 8'h00;
                overflow_q <= 1'b0;
                rx_error_sticky_q <= 1'b0;
              end
              if (rx_byte[3]) begin
                if (!trace_pending_q) begin
                  trace_pending_q <= 1'b1;
                  trace_sample_q <= probe_i;
                  trace_delta_q <= delta_q;
                  trace_change_q <= 8'h00;
                end else begin
                  overflow_q <= 1'b1;
                  if (drop_count_q != 8'hff) begin
                    drop_count_q <= drop_count_q + 8'h01;
                  end
                end
              end
            end
            CMD_PATTERN_MODE: begin
              pattern_mode_q <= rx_byte[2:0];
            end
            CMD_PATTERN_DIV: begin
              pattern_div_q <= rx_byte[5:0];
            end
            CMD_PATTERN_A: begin
              pattern_a_q <= rx_byte;
            end
            default: begin
            end
          endcase
        end else begin
          case (rx_byte)
            CMD_TRACE_MASK,
            CMD_SAMPLE_DIV,
            CMD_TRACE_CTRL,
            CMD_PATTERN_MODE,
            CMD_PATTERN_DIV,
            CMD_PATTERN_A: begin
              wait_arg_q <= 1'b1;
              cmd_q <= rx_byte;
            end
            CMD_STATUS: begin
              status_pending_q <= 1'b1;
            end
            CMD_PING: begin
              ping_pending_q <= 1'b1;
            end
            default: begin
            end
          endcase
        end
      end

      if (!pkt_active_q) begin
        if (ping_pending_q) begin
          pkt_active_q <= 1'b1;
          pkt_kind_q <= PKT_KIND_PING;
          pkt_index_q <= 2'd0;
          ping_pending_q <= 1'b0;
        end else if (status_pending_q) begin
          pkt_active_q <= 1'b1;
          pkt_kind_q <= PKT_KIND_STATUS;
          pkt_index_q <= 2'd0;
          status_pending_q <= 1'b0;
        end else if (trace_pending_q) begin
          pkt_active_q <= 1'b1;
          pkt_kind_q <= PKT_KIND_TRACE;
          pkt_index_q <= 2'd0;
          trace_pending_q <= 1'b0;
        end
      end else if (tx_ready) begin
        if (pkt_index_q == 2'd3) begin
          pkt_active_q <= 1'b0;
          pkt_index_q <= 2'd0;
        end else begin
          pkt_index_q <= pkt_index_q + 2'd1;
        end
      end

      if (pattern_tick) begin
        pattern_cnt_q <= pattern_div_q;
        case (pattern_mode_q)
          3'd0: begin
            pattern_out_q <= pattern_a_q;
          end
          3'd1: begin
            pattern_out_q <= pattern_out_q + 8'h01;
          end
          3'd2: begin
            if (pattern_out_q == 8'h00) begin
              pattern_out_q <= 8'h01;
            end else begin
              pattern_out_q <= {pattern_out_q[6:0], pattern_out_q[7]};
            end
          end
          3'd3: begin
            if (pattern_out_q == 8'h00) begin
              pattern_out_q <= pattern_a_q == 8'h00 ? 8'h01 : pattern_a_q;
            end else begin
              pattern_out_q <= {pattern_out_q[6:0],
                                pattern_out_q[7] ^ pattern_out_q[5] ^
                                pattern_out_q[4] ^ pattern_out_q[3]};
            end
          end
          3'd4: begin
            pattern_out_q <= ~pattern_a_q;
          end
          3'd5: begin
            pattern_out_q <= probe_i;
          end
          default: begin
            pattern_out_q <= probe_i ^ pattern_a_q;
          end
        endcase
      end else begin
        pattern_cnt_q <= pattern_cnt_q - 6'h01;
      end

      if (sample_tick) begin
        sample_cnt_q <= sample_div_q;
        if (armed_q && stream_q) begin
          if (trace_event) begin
            if (!trace_pending_q) begin
              trace_pending_q <= 1'b1;
              trace_sample_q <= probe_i;
              trace_delta_q <= delta_q;
              trace_change_q <= change_mask;
            end else begin
              overflow_q <= 1'b1;
              if (drop_count_q != 8'hff) begin
                drop_count_q <= drop_count_q + 8'h01;
              end
            end
            if (event_count_q != 8'hff) begin
              event_count_q <= event_count_q + 8'h01;
            end
            event_toggle_q <= !event_toggle_q;
            delta_q <= 8'h00;
          end else if (delta_q != 8'hff) begin
            delta_q <= delta_q + 8'h01;
          end
          last_sample_q <= probe_i;
        end
      end else begin
        sample_cnt_q <= sample_cnt_q - 4'h1;
      end
    end
  end

endmodule

module detronyx_uart_tx #(
    parameter [8:0] BAUD_RELOAD = 9'd433
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        ce_i,
    input  wire [7:0]  data_i,
    input  wire        valid_i,
    output wire        ready_o,
    output wire        tx_o,
    output wire        busy_o
);

  reg [9:0]  shift_q;
  reg [8:0]  timer_q;
  reg [3:0]  bit_count_q;
  reg        busy_q;

  assign ready_o = !busy_q;
  assign tx_o = busy_q ? shift_q[0] : 1'b1;
  assign busy_o = busy_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      shift_q <= 10'h3ff;
      timer_q <= 9'h000;
      bit_count_q <= 4'd0;
      busy_q <= 1'b0;
    end else if (ce_i) begin
      if (!busy_q) begin
        if (valid_i) begin
          shift_q <= {1'b1, data_i, 1'b0};
          timer_q <= BAUD_RELOAD;
          bit_count_q <= 4'd10;
          busy_q <= 1'b1;
        end
      end else if (timer_q == 9'h000) begin
        shift_q <= {1'b1, shift_q[9:1]};
        timer_q <= BAUD_RELOAD;
        if (bit_count_q == 4'd1) begin
          busy_q <= 1'b0;
          bit_count_q <= 4'd0;
        end else begin
          bit_count_q <= bit_count_q - 4'd1;
        end
      end else begin
        timer_q <= timer_q - 9'd1;
      end
    end
  end

endmodule

module detronyx_uart_rx #(
    parameter [8:0] BAUD_RELOAD = 9'd433
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        ce_i,
    input  wire        rx_i,
    output reg  [7:0]  data_o,
    output reg         valid_o,
    output reg         frame_error_o
);

  localparam [1:0] RX_IDLE  = 2'd0;
  localparam [1:0] RX_START = 2'd1;
  localparam [1:0] RX_DATA  = 2'd2;
  localparam [1:0] RX_STOP  = 2'd3;
  localparam [8:0] BAUD_HALF_RELOAD = BAUD_RELOAD >> 1;

  reg [1:0]  state_q;
  reg [8:0]  timer_q;
  reg [2:0]  bit_index_q;
  reg [7:0]  shift_q;
  reg        rx_meta_q;
  reg        rx_sync_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= RX_IDLE;
      timer_q <= 9'h000;
      bit_index_q <= 3'd0;
      shift_q <= 8'h00;
      rx_meta_q <= 1'b1;
      rx_sync_q <= 1'b1;
      data_o <= 8'h00;
      valid_o <= 1'b0;
      frame_error_o <= 1'b0;
    end else if (ce_i) begin
      rx_meta_q <= rx_i;
      rx_sync_q <= rx_meta_q;
      valid_o <= 1'b0;
      frame_error_o <= 1'b0;

      case (state_q)
        RX_IDLE: begin
          if (!rx_sync_q) begin
            state_q <= RX_START;
            timer_q <= BAUD_HALF_RELOAD;
          end
        end
        RX_START: begin
          if (timer_q == 9'h000) begin
            if (!rx_sync_q) begin
              state_q <= RX_DATA;
              timer_q <= BAUD_RELOAD;
              bit_index_q <= 3'd0;
            end else begin
              state_q <= RX_IDLE;
            end
          end else begin
            timer_q <= timer_q - 9'd1;
          end
        end
        RX_DATA: begin
          if (timer_q == 9'h000) begin
            shift_q <= {rx_sync_q, shift_q[7:1]};
            timer_q <= BAUD_RELOAD;
            if (bit_index_q == 3'd7) begin
              state_q <= RX_STOP;
            end else begin
              bit_index_q <= bit_index_q + 3'd1;
            end
          end else begin
            timer_q <= timer_q - 9'd1;
          end
        end
        default: begin
          if (timer_q == 9'h000) begin
            data_o <= shift_q;
            valid_o <= rx_sync_q;
            frame_error_o <= !rx_sync_q;
            state_q <= RX_IDLE;
          end else begin
            timer_q <= timer_q - 9'd1;
          end
        end
      endcase
    end
  end

endmodule

`default_nettype wire
