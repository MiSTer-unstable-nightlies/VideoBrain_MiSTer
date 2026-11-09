`timescale 1ns/1ps
module tb_status_messages;
reg clk = 0;
always #5 clk = ~clk;
reg reset = 1, osd = 0, vs = 0;
reg [127:0] status = 0;
reg started = 0, complete = 0, source_error = 0;
reg aborted = 0, calibrating = 0;
reg busy = 0, tape_error = 0, rewound = 0, ended = 0, cart_loaded = 0;
reg cart_error = 0;
integer messages = 0, before_count;
reg [3:0] printer_state=0, printer_fault=0;
reg printer_busy=0,printer_active=0;
reg [7:0] last_info = 0;
reg [1:0] deck_rewound = 0, deck_busy = 0, deck_mounted = 0;
reg [63:0] img_size = 0;
reg field = 0;
emu dut ();

always @(negedge clk) begin
    if (dut.info_req) begin
        if (osd || status[22]) $fatal(1, "Popup while menu open or messages disabled");
        messages = messages + 1;
        last_info = dut.info;
    end
    if (dut.menu_mask[8] !== !busy)
        $fatal(1, "Tape mounting guard does not follow busy");
    if (dut.menu_mask[10] !== !cart_loaded)
        $fatal(1, "Cartridge unloading guard changed");
    if (dut.menu_mask[5] !== status[19])
        $fatal(1, "Music mode guard does not follow repeat");
end

task tick;
    @(posedge clk); #1;
    @(negedge clk); #1;
endtask

task frame;
    vs = 0; tick;
    vs = 1; tick;
    vs = 0; tick;
endtask

task expect_message(input [7:0] code);
    integer previous;
    previous = messages;
    frame;
    if (messages != previous + 1 || last_info != code)
        $fatal(1, "Missing popup %0d (last %0d)", code, last_info);
endtask

initial begin
    force dut.printer_status = printer_state;
    force dut.printer_error = printer_fault;
    force dut.printer_busy = printer_busy;
    force dut.printer_active = printer_active;
    force dut.clk_sys = clk;
    force dut.reset = reset;
    force dut.status = status;
    force dut.OSD_STATUS = osd;
    force dut.vid_vs = vs;
    force dut.source_started = started;
    force dut.source_complete = complete;
    force dut.source_error = source_error;
    force dut.source_aborted = aborted;
    force dut.joy_calibrating = calibrating;
    force dut.tape_busy = busy;
    force dut.tape_error = tape_error;
    force dut.tape_rewound = rewound;
    force dut.tape_ended = ended;
    force dut.cart_loaded = cart_loaded;
    force dut.cart_load_error = cart_error;
    force dut.joystick_connected = 1'b1;
    force dut.tape_deck_rewound = deck_rewound;
    force dut.tape_deck_busy = deck_busy;
    force dut.tape_mounted = deck_mounted;
    force dut.tape_size = img_size;
    force dut.vid_field = field;
    tick; reset = 0; tick;
    osd = 1; tick;
    if (dut.source_enabled) $fatal(1, "Entry enabled in OSD by default");
    status[31] = 1; tick;
    if (dut.source_enabled) $fatal(1, "Keep-alive started entry inside OSD");
    started = 1; tick;
    if (!dut.source_enabled) $fatal(1, "Keep-alive disabled active entry");
    status[31] = 0; tick;
    if (dut.source_enabled) $fatal(1, "OSD abort option ignored");
    started = 0; tick;
    osd = 0; frame;
    status[18] = 1; tick;
    if (dut.source_music_playback) $fatal(1, "Record mode ignored");
    status[19] = 1; tick;
    if (!dut.source_music_playback) $fatal(1, "Repeat did not select playback");
    status[19] = 0; tick;
    if (dut.source_music_playback) $fatal(1, "Record selection lost after repeat");
    started = 1; tick; expect_message(1);
    complete = 1; tick; expect_message(7);
    source_error = 1; tick; expect_message(2);
    before_count = messages;
    repeat (4) frame;
    if (messages != before_count) $fatal(1, "Repeated latched keyboard notice");

    osd = 1;
    aborted = 1; tick; frame;
    if (messages != before_count) $fatal(1, "Abort notice bypassed OSD deferral");
    osd = 0; expect_message(8);
    calibrating = 1; tick; expect_message(9);
    before_count = messages;
    repeat (59) frame;
    if (messages != before_count) $fatal(1, "Calibration refreshed too soon");
    expect_message(9);
    calibrating = 0; tick;
    before_count = messages;
    repeat (65) frame;
    if (messages != before_count) $fatal(1, "Calibration popup refreshed after completion");
    osd = 1; calibrating = 1; tick;
    calibrating = 0; tick;
    osd = 0; frame;
    if (messages != before_count) $fatal(1, "Stale calibration notice");

    busy = 1; tick; expect_message(5);
    before_count = messages;
    repeat (59) frame;
    if (messages != before_count) $fatal(1, "Busy popup refreshed too soon");
    expect_message(5);
    cart_loaded = 1; tick;
    busy = 0; tick; expect_message(6);
    before_count = messages;
    repeat (65) frame;
    if (messages != before_count) $fatal(1, "Busy popup refreshed while idle");

    osd = 1;
    busy = 1; tick; frame;
    busy = 0; tick; frame;
    if (messages != before_count) $fatal(1, "Lost menu deferral");
    osd = 0; expect_message(6);
    rewound = 1; tick; rewound = 0; expect_message(4);

    busy = 1; tick; expect_message(5);
    osd = 1;
    ended = 1; tick; ended = 0;
    busy = 0; tick; frame;
    osd = 0; expect_message(10);
    before_count = messages;
    repeat (65) frame;
    if (messages != before_count) $fatal(1, "End of tape notice repeated or became idle");

    busy = 1; tick; expect_message(5);
    busy = 0; tape_error = 1; tick; expect_message(3);
    before_count = messages;
    repeat (65) frame;
    if (messages != before_count) $fatal(1, "Idle or busy popup obscured tape error");

    osd = 1;
    rewound = 1; tick; rewound = 0;
    reset = 1; tick; reset = 0; osd = 0; frame;
    if (messages != before_count) $fatal(1, "Reset retained a stale popup");

    rewound = 1; tick; rewound = 0;
    status[22] = 1; tick; frame;
    started = 0; complete = 0; source_error = 0; tape_error = 0; aborted = 0; tick;
    started = 1; complete = 1; source_error = 1;
    aborted = 1; calibrating = 1;
    tape_error = 1; rewound = 1; busy = 1; tick;
    rewound = 0; repeat (65) frame;
    busy = 0; tick;
    if (messages != before_count || dut.pending_info != 0)
        $fatal(1, "Disabled messages were emitted or queued");
    status[22] = 0; frame;
    if (messages != before_count) $fatal(1, "Enabling messages replayed an old event");
    rewound = 1; tick; rewound = 0; expect_message(4);
    osd=1; printer_state=2;tick();
    if(!dut.menu_mask[6] || !dut.menu_mask[7]) $fatal(1,"Ready printer actions unavailable");
    printer_state=4;printer_busy=1;printer_active=1;tick();
    if(dut.menu_mask[6] || dut.menu_mask[7] || !dut.menu_mask[9])
        $fatal(1,"Active printer mount/start guard failed");
    printer_state=8;printer_fault=6;printer_active=0;tick();
    printer_state=1;printer_fault=0;tick();
    if(dut.printer_notice!=20) $fatal(1,"Printer error overwritten by status");
    osd=0;expect_message(20);
    osd=1;printer_state=2;printer_busy=0;tick();
    status[36]=1;tick();status[36]=0;tick();
    osd=0;expect_message(13);
    printer_state=1;tick();printer_state=2;tick();expect_message(13);
    printer_state=3;tick();printer_state=4;tick();expect_message(16);
    before_count = messages;
    printer_state=6;tick();printer_state=4;tick();frame;
    printer_state=3;tick();frame;
    if (messages != before_count) $fatal(1, "Transient printer state raised a popup");
    printer_state=4;tick();expect_message(16);
    printer_state=5;tick();frame;
    if (messages != before_count + 1) $fatal(1, "Flushing raised a popup");
    printer_state=2;tick();expect_message(17);
    printer_fault=8;printer_state=7;tick();expect_message(18);
    printer_fault=2;printer_state=8;tick();expect_message(19);
    printer_fault=0;printer_state=2;tick();
    before_count = messages; frame;
    if (messages != before_count) $fatal(1, "Recovery from error raised a popup");
    status[22]=1;printer_fault=5;printer_state=8;tick();frame;
    if(dut.printer_notice!=0) $fatal(1,"Disabled printer notice queued");
    status[22]=0;tick();frame;
    osd = 1; cart_error = 1; tick;
    before_count = messages; frame;
    if (messages != before_count) $fatal(1, "Cartridge error bypassed OSD deferral");
    osd = 0; expect_message(11);
    before_count = messages; repeat (3) frame;
    if (messages != before_count) $fatal(1, "Cartridge error repeated");

    // in-menu status lines
    osd = 1; tick;
    if (dut.menu_mask[3:0] != 0) $fatal(1, "Status lines shown without events");
    status[42:41] = 2; tick; tick;
    if (!dut.menu_mask[0]) $fatal(1, "Changes Pending missing");
    status[43] = 1; tick; status[43] = 0; tick; tick;
    if (!dut.menu_mask[0]) $fatal(1, "Changes Pending cleared before the field switch");
    field = 1; tick; tick; tick;
    if (dut.menu_mask[0]) $fatal(1, "Changes Pending stayed after apply");
    deck_rewound = 1; tick; deck_rewound = 0; tick;
    if (dut.menu_mask[3:2] != 2'b01) $fatal(1, "Playback rewound line wrong");
    deck_busy = 1; tick; tick;
    if (dut.menu_mask[2]) $fatal(1, "Playback rewound survived deck motion");
    deck_rewound = 1; tick; deck_rewound = 0; tick;
    if (!dut.menu_mask[2]) $fatal(1, "Rewind during busy not reported");
    deck_busy = 0;
    deck_rewound = 2; tick; deck_rewound = 0; tick;
    if (dut.menu_mask[3:2] != 2'b11) $fatal(1, "Record rewound line wrong");
    img_size = 8*1024*1024; deck_mounted = 2; tick; deck_mounted = 0; tick;
    if (dut.menu_mask[3] || !dut.menu_mask[2]) $fatal(1, "Record mount did not clear only its rewound line");
    repeat (3) frame;
    status[46] = 1; tick; status[46] = 0; tick;
    if (!dut.menu_mask[1]) $fatal(1, "Tape Created missing");
    osd = 0; tick; tick;
    if (dut.menu_mask[3:1] != 0) $fatal(1, "Event lines survived OSD close");
    osd = 1; status[46] = 1; tick; status[46] = 0; tick;
    if (dut.menu_mask[1]) $fatal(1, "Tape Created without a new mount");
    deck_mounted = 2; tick; deck_mounted = 0; tick;
    repeat (61) frame;
    status[46] = 1; tick; status[46] = 0; tick;
    if (dut.menu_mask[1]) $fatal(1, "Tape Created after a stale mount");
    $display("Status popup and tape menu guard tests passed");
    $finish;
end
endmodule
