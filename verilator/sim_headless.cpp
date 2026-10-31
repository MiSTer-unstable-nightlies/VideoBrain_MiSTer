
#include <verilated.h>
#include "Vtop.h"
#include "Vtop___024root.h"

#include <zlib.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <set>

#define CORE(sig) (top->rootp->top__DOT__core__DOT__##sig)
#define CPU(sig)  (top->rootp->top__DOT__core__DOT__u_cpu__DOT__##sig)
#define BUS(sig)  (top->rootp->top__DOT__core__DOT__u_sys_bus__DOT__##sig)
#define UVR(sig)  (top->rootp->top__DOT__core__DOT__u_sys_bus__DOT__u_uv201_regs__DOT__##sig)
#define FET(sig)  (top->rootp->top__DOT__core__DOT__u_fetcher__DOT__##sig)
#define SMI(sig)  (top->rootp->top__DOT__core__DOT__u_smi__DOT__##sig)
#define RES1      BUS(res1_rom)
#define RES2      BUS(res2_rom)
#define CART      BUS(cart_rom)
#define SYSRAM    BUS(sys_ram)

static Vtop* top = nullptr;
static vluint64_t main_time = 0;

static std::vector<uint32_t> read_tape(const std::string& path) {
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) { fprintf(stderr, "error: cannot read %s\n", path.c_str()); exit(1); }
    uint8_t header[512];
    auto le32 = [](const uint8_t* p) {
        return uint32_t(p[0]) | uint32_t(p[1]) << 8 |
               uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
    };
    if (fread(header, 1, sizeof(header), f) != sizeof(header) ||
        memcmp(header, "VBT1", 4) || le32(header + 4) != 14318180) {
        fprintf(stderr, "error: invalid VBT1 header\n"); exit(1);
    }
    uint32_t count = le32(header + 8);
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    if (size < 512 || count == 0 || count > uint64_t(size - 512) / 4) {
        fprintf(stderr, "error: invalid VBT1 interval count\n"); exit(1);
    }
    fseek(f, 512, SEEK_SET);
    std::vector<uint32_t> samples(count);
    for (uint32_t& sample : samples) {
        uint8_t bytes[4];
        if (fread(bytes, 1, 4, f) != 4) {
            fprintf(stderr, "error: truncated VBT1 data\n"); exit(1);
        }
        sample = le32(bytes);
        if ((sample & 0x7fffffff) < 2) {
            fprintf(stderr, "error: invalid VBT1 duration\n"); exit(1);
        }
    }
    fclose(f);
    return samples;
}
double sc_time_stamp() { return (double)main_time; }

// obj_ram survives ghdl synth as one flat 1152-bit vector rather than an
// array: it has two asynchronous read ports, so nothing infers it as ram
// the vhdl array ascends (0 to 143) and flattens with element 0 at the top of
// the vector, so index from the far end
static uint8_t obj_byte(int i) {
    const uint32_t* w = UVR(obj_ram).data();
    int bit = (143 - i) * 8;
    uint32_t lo = w[bit >> 5] >> (bit & 31);
    if ((bit & 31) > 24) lo |= (uint32_t)w[(bit >> 5) + 1] << (32 - (bit & 31));
    return (uint8_t)lo;
}

static void put_be32(std::vector<uint8_t>& v, uint32_t x) {
    v.push_back((x >> 24) & 0xff); v.push_back((x >> 16) & 0xff);
    v.push_back((x >> 8) & 0xff);  v.push_back(x & 0xff);
}

static void png_chunk(FILE* f, const char* type, const uint8_t* data, size_t len) {
    std::vector<uint8_t> hdr;
    put_be32(hdr, (uint32_t)len);
    fwrite(hdr.data(), 1, hdr.size(), f);
    fwrite(type, 1, 4, f);
    if (len) fwrite(data, 1, len, f);
    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const Bytef*)type, 4);
    if (len) crc = crc32(crc, (const Bytef*)data, (uInt)len);
    std::vector<uint8_t> tail;
    put_be32(tail, (uint32_t)crc);
    fwrite(tail.data(), 1, tail.size(), f);
}

static bool write_png(const std::string& path, int w, int h, const std::vector<uint8_t>& rgb) {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) { fprintf(stderr, "error: cannot write %s\n", path.c_str()); return false; }

    static const uint8_t sig[8] = { 137, 'P', 'N', 'G', '\r', '\n', 26, '\n' };
    fwrite(sig, 1, 8, f);

    std::vector<uint8_t> ihdr;
    put_be32(ihdr, (uint32_t)w);
    put_be32(ihdr, (uint32_t)h);
    ihdr.push_back(8);              // bit depth
    ihdr.push_back(2);              // colour type: truecolour rgb
    ihdr.push_back(0);
    ihdr.push_back(0);
    ihdr.push_back(0);
    png_chunk(f, "IHDR", ihdr.data(), ihdr.size());

    std::vector<uint8_t> raw;
    raw.reserve((size_t)h * (1 + (size_t)w * 3));
    for (int y = 0; y < h; y++) {
        raw.push_back(0);           // filter type 0
        raw.insert(raw.end(), rgb.begin() + (size_t)y * w * 3,
                              rgb.begin() + (size_t)(y + 1) * w * 3);
    }

    uLongf clen = compressBound((uLong)raw.size());
    std::vector<uint8_t> comp(clen);
    if (compress2(comp.data(), &clen, raw.data(), (uLong)raw.size(), 9) != Z_OK) {
        fprintf(stderr, "error: zlib compress failed\n"); fclose(f); return false;
    }
    png_chunk(f, "IDAT", comp.data(), clen);
    png_chunk(f, "IEND", nullptr, 0);
    fclose(f);
    return true;
}

static bool write_ppm(const std::string& path, int w, int h, const std::vector<uint8_t>& rgb) {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) { fprintf(stderr, "error: cannot write %s\n", path.c_str()); return false; }
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    fwrite(rgb.data(), 1, rgb.size(), f);
    fclose(f);
    return true;
}

static const int MAX_W = 512;
static const int MAX_H = 512;

static inline char ascii_for(uint8_t idx) {
    static const char* lo = " rgybmcw";
    static const char* hi = ".RGYBMCW";
    return (idx & 0x10) ? hi[idx & 7] : lo[idx & 7];
}

static inline void idx_to_rgb(uint8_t idx, uint8_t& r, uint8_t& g, uint8_t& b) {
    uint8_t off = (idx & 0x10) ? 0xC0 : 0x00;
    uint8_t on  = (idx & 0x10) ? 0xFF : 0xA0;
    r = (idx & 1) ? on : off;
    g = (idx & 2) ? on : off;
    b = (idx & 4) ? on : off;
}

struct FrameGrabber {
    std::vector<uint8_t> pix;
    int col = 0, line = 0;
    int width = 0, height = 0;
    int last_width = 0, last_height = 0;
    bool prev_vs = false, prev_hs = false;
    long frame = 0;
    bool complete = false;

    FrameGrabber() : pix((size_t)MAX_W * MAX_H, 0) {}

    bool clock(bool vs, bool hs, bool de, uint8_t idx) {
        bool boundary = false;

        if (vs && !prev_vs) {
            last_width = width; last_height = height;
            if (last_width > 0 && last_height > 0) complete = true;
            frame++;
            boundary = true;
        }

        if (hs && !prev_hs) {
            if (col > 0) line++;
            col = 0;
        }

        if (boundary) { line = 0; col = 0; width = 0; height = 0; }

        if (de && line < MAX_H && col < MAX_W) {
            pix[(size_t)line * MAX_W + col] = idx;
            col++;
            if (col > width) width = col;
            if (line + 1 > height) height = line + 1;
        }

        prev_vs = vs; prev_hs = hs;
        return boundary;
    }

    void to_rgb(std::vector<uint8_t>& out, int& w, int& h, int scale) const {
        w = last_width * scale;
        h = last_height * scale;
        out.assign((size_t)w * h * 3, 0);
        for (int y = 0; y < last_height; y++) {
            for (int x = 0; x < last_width; x++) {
                uint8_t r, g, b;
                idx_to_rgb(pix[(size_t)y * MAX_W + x], r, g, b);
                for (int sy = 0; sy < scale; sy++) {
                    for (int sx = 0; sx < scale; sx++) {
                        size_t o = (((size_t)y * scale + sy) * w + ((size_t)x * scale + sx)) * 3;
                        out[o] = r; out[o + 1] = g; out[o + 2] = b;
                    }
                }
            }
        }
    }

    void to_ascii(FILE* f) const {
        fprintf(f, "    +");
        for (int x = 0; x < last_width; x++) fputc('-', f);
        fprintf(f, "+\n");
        for (int y = 0; y < last_height; y++) {
            fprintf(f, "%3d |", y);
            for (int x = 0; x < last_width; x++)
                fputc(ascii_for(pix[(size_t)y * MAX_W + x]), f);
            fprintf(f, "|\n");
        }
        fprintf(f, "    +");
        for (int x = 0; x < last_width; x++) fputc('-', f);
        fprintf(f, "+\n");
    }

    uint32_t hash() const {
        uint32_t h = 2166136261u;
        for (int y = 0; y < last_height; y++)
            for (int x = 0; x < last_width; x++)
                h = (h ^ pix[(size_t)y * MAX_W + x]) * 16777619u;
        return h;
    }

    bool blank() const {
        if (last_width <= 0 || last_height <= 0) return true;
        uint8_t first = pix[0];
        for (int y = 0; y < last_height; y++)
            for (int x = 0; x < last_width; x++)
                if (pix[(size_t)y * MAX_W + x] != first) return false;
        return true;
    }
};

struct KeyName { const char* name; int bit; };
static const KeyName KEYS[] = {
    {"I",0},{"O",1},{"P",2},{"SEMI",3},
    {"U",4},{"K",5},{"L",6},{"QUOTE",7},
    {"Y",8},{"J",9},{"M",10},{"SHIFT",11},
    {"T",12},{"H",13},{"N",14},{"ERASE",15},
    {"R",16},{"G",17},{"B",18},{"SPACE",19},
    {"E",20},{"F",21},{"V",22},{"SPECIAL",23},
    {"W",24},{"D",25},{"C",26},{"NEXT",27},
    {"Q",28},{"S",29},{"X",30},{"PREVIOUS",31},
    {"A",32},{"Z",33},{"QUESTION",34},{"BACK",35},
    {"ESC",36},
};

static int key_bit(const std::string& n) {
    for (const KeyName& k : KEYS) if (n == k.name) return k.bit;
    return -1;
}

struct Download { std::string path; int index; };

struct IoctlDriver {
    std::vector<Download> queue;
    size_t qpos = 0;
    std::vector<uint8_t> data;
    size_t pos = 0;
    int gap = 0;
    bool active = false;
    bool finished = false;
    bool quiet = false;

    void add(const std::string& path, int index) { queue.push_back({ path, index }); }

    bool load_next() {
        while (qpos < queue.size()) {
            const Download& d = queue[qpos++];
            FILE* f = fopen(d.path.c_str(), "rb");
            if (!f) { fprintf(stderr, "error: cannot open %s\n", d.path.c_str()); exit(2); }
            fseek(f, 0, SEEK_END);
            long n = ftell(f);
            fseek(f, 0, SEEK_SET);
            data.resize((size_t)n);
            if (n > 0 && fread(data.data(), 1, (size_t)n, f) != (size_t)n) {
                fprintf(stderr, "error: short read on %s\n", d.path.c_str()); exit(2);
            }
            fclose(f);

            pos = 0;
            active = true;
            top->ioctl_index = (uint8_t)d.index;
            if (!quiet)
                fprintf(stderr, "[ioctl] %s -> index %d (%ld bytes)\n",
                        d.path.c_str(), d.index, n);
            return true;
        }
        finished = true;
        return false;
    }

    void tick() {
        if (!active) {
            top->ioctl_download = 0;
            top->ioctl_wr = 0;
            if (gap > 0) { gap--; return; }
            if (!finished) load_next();
            return;
        }
        if (pos < data.size()) {
            top->ioctl_download = 1;
            top->ioctl_wr = 1;
            top->ioctl_addr = (uint32_t)pos;
            top->ioctl_dout = data[pos];
            pos++;
        } else {
            top->ioctl_download = 0;
            top->ioctl_wr = 0;
            active = false;
            gap = 256;   // let reset settle between downloads
        }
    }
};

static void dump_state(FILE* f, long frame, const FrameGrabber& fg, bool want_ram) {
    fprintf(f, "\n========== frame %ld (t=%llu) ==========\n",
            frame, (unsigned long long)main_time);

    fprintf(f, "-- F8 --\n");
    fprintf(f, "PC0=%04X PC1=%04X DC0=%04X  acc=%02X visar=%02X romc=%02X phase=%X\n",
            (unsigned)top->rootp->top__DOT__pc0, (unsigned)top->rootp->top__DOT__pc1,
            (unsigned)top->rootp->top__DOT__dc0,
            (unsigned)CPU(acc), (unsigned)CPU(visar),
            (unsigned)CORE(romc), (unsigned)CORE(phase));

    fprintf(f, "scratch 0-F:");
    for (int i = 0; i < 16; i++) fprintf(f, " %02X", (unsigned)CPU(scratch_regs)[i]);
    fprintf(f, "\nISAR=%02X (S)=%02X  buffer 10-1F:",
            (unsigned)CPU(visar), (unsigned)CPU(scratch_regs)[CPU(visar) & 63]);
    for (int i = 0x10; i < 0x20; i++) fprintf(f, " %02X", (unsigned)CPU(scratch_regs)[i]);
    fprintf(f, "\n");

    fprintf(f, "-- UV201 --\n");
    fprintf(f, "cmd=%02X bg=%02X fmod=%02X y_int=%02X  video_en=%d x_zoom=%d y_zoom=%d\n",
            (unsigned)UVR(r_cmd), (unsigned)UVR(r_bg), (unsigned)UVR(r_fmod),
            (unsigned)UVR(r_y_int),
            (int)top->rootp->top__DOT__video_en,
            (int)top->rootp->top__DOT__x_zoom,
            (int)top->rootp->top__DOT__y_zoom);
    fprintf(f, "hpos=%3d vpos=%3d field=%d fifo_level=%d\n",
            (int)top->rootp->top__DOT__hpos, (int)top->rootp->top__DOT__vpos,
            (int)CORE(field_l), (int)top->rootp->top__DOT__fifo_level);
    fprintf(f, "freeze_x=%d freeze_y=%d joy_enable=%d joy_latch=%02X\n",
            (int)UVR(r_freeze_x), (int)UVR(r_freeze_y),
            (int)CORE(joy_enable_l), (unsigned)CORE(key_latch_l));

    fprintf(f, "-- object list (rp_lo rp_hi dx dy x ylo_a yhi_a ylo_b yhi_b) --\n");
    for (int i = 0; i < 16; i++) {
        fprintf(f, "%2d: %02X %02X %02X %02X %02X  %02X %02X  %02X %02X\n", i,
                obj_byte(0x00 + i), obj_byte(0x10 + i), obj_byte(0x20 + i),
                obj_byte(0x30 + i), obj_byte(0x40 + i),
                obj_byte(0x50 + i), obj_byte(0x70 + i),
                obj_byte(0x60 + i), obj_byte(0x80 + i));
    }

    fprintf(f, "-- frame %dx%d hash %08X %s --\n",
            fg.last_width, fg.last_height, fg.hash(), fg.blank() ? "uniform" : "");

    if (want_ram) {
        fprintf(f, "-- system RAM 0C00-0FFF --\n");
        for (int i = 0; i < 1024; i += 16) {
            fprintf(f, "%04X: ", 0x0C00 + i);
            for (int j = 0; j < 16; j++) fprintf(f, "%02X ", (unsigned)SYSRAM[i + j]);
            fprintf(f, "\n");
        }
    }
    fflush(f);
}

static void usage(const char* argv0) {
    fprintf(stderr,
"Headless VideoBrain simulator\n"
"Usage: %s [options]\n"
"\n"
"  --res1 FILE          required RES1 ROM, ioctl index 0\n"
"  --res2 FILE          optional RES2 ROM, ioctl index 1\n"
"  --expander1 FILE     Expander 1 firmware, ioctl index 3 (experimental)\n"
"  --record FILE        diagnostic cassette edges (MCLK cycle, level, remote)\n"
"  --playback FILE      replay VBT1 waveform at the Expander cassette input\n"
"  --expander-trace FILE  log host signals and VideoBrain PC\n"
"  --cart FILE          cartridge image, ioctl index 2 (2K images are mirrored)\n"
"  --source FILE@F      enter a VBK keyboard file through RTL\n"
"  --source-trace       log generated keys and interpreter mode\n"
"  --source-snoop FILE  passive CSV: keys, mode, RAM writes, I/O, scratch writes\n"
"  --source-snoop-from N  start at loader payload position N (default 0)\n"
"  --cart-type N        fallback profile: 0 standard, 1 Timeshare, 2 Money Minder, 3 CompLang, 4 Infoman, 5 4K RAM, 6 BASIC\n"
"\n"
"  --frames N           stop after N video frames (default 300)\n"
"  --max-cycles N       hard cycle cap (default 2000000000)\n"
"  --240p               use the core's 240p timing (default off)\n"
"\n"
"  --shot N[,N...]      capture at these frame numbers\n"
"  --shot-every N       capture every N frames\n"
"  --shot-last          capture the final frame\n"
"  --outdir DIR         output directory (default ./out)\n"
"  --prefix NAME        filename prefix (default from cart/res1 name)\n"
"  --scale N            pixel scale for PNG output (default 3)\n"
"  --ppm                also write .ppm alongside the .png\n"
"  --ascii              also print the frame as ASCII art\n"
"\n"
"  --dump N[,N...]      dump CPU/UV201 state at these frames\n"
"  --dump-every N       dump every N frames\n"
"  --ram                include the 1K system RAM in state dumps\n"
"  --dump-file FILE     write dumps here instead of stdout\n"
"\n"
"  --trace-cpu N        log the first N CPU memory cycles (PC0, ROMC)\n"
"  --trace-from F       only start the trace at frame F\n"
"  --money-trace        log Money Minder key dispatch registers\n"
"  --audio-log FILE     log DAC latch events and interrupt state as CSV\n"
"  --audio-trace FILE   trace keys, sound pins, latch checks and IRQ edges\n"
"  --press KEY@F[:H[:C]]  hold KEY from F to F+H (default H=8).\n"
"                       C delays key-down by 0..239855 MCLKs (default 0).\n"
"                       ESC = MASTER CONTROL; H uses nominal field cycles.\n"
"                       RUN/STOP is SPACE. Letters are their own names;\n"
"                       also SHIFT ERASE SPECIAL NEXT PREVIOUS BACK\n"
"                       SEMI QUOTE QUESTION. Repeatable.\n"
"  --joy DIR@F[:H]     hold player 1 UP/DOWN/LEFT/RIGHT/FIRE. Repeatable.\n"
"  --joy2 DIR@F[:H]    hold player 2 UP/DOWN/LEFT/RIGHT/FIRE. Repeatable.\n"
"  --joy-pot C:V@F:H   override pot channel 0..7 with 0..255 for H frames; last wins.\n"
"  --frame-log          one line per frame with size and hash\n"
"  --probe              per-frame UV201 fetcher/FIFO activity counters\n"
"  --joy-trace F        log joystick control and freeze changes from frame F\n"
"  --joy-focus F        trace joystick timing and BIOS operands only in frame F\n"
"  --joy-results F      log BIOS joystick returns and bounds from frame F\n"
"  --joy-return-pc HEX  joystick return instruction (default 22BE; Tennis 1FCB)\n"
"  --joy-timer-base N   manual 555 pulse base in MCLK ticks (default 2580)\n"
"  --joy-timer-step N   manual MCLK ticks per pot count (default 7)\n"
"                      otherwise use the cartridge's linear preset\n"
"  --joy-timer-curve    shared 1620:23/53 curve, split at pot128\n"
"  --joy-timer-sweep LIST  cycle base:step candidates independently per axis\n"
"  --quiet              suppress progress output\n", argv0);
}

static void parse_list(const char* s, std::set<long>& out) {
    const char* p = s;
    while (*p) {
        char* end;
        long v = strtol(p, &end, 0);
        if (end == p) break;
        out.insert(v);
        p = (*end == ',') ? end + 1 : end;
    }
}

static std::string basename_noext(const std::string& p) {
    size_t a = p.find_last_of("/\\");
    std::string b = (a == std::string::npos) ? p : p.substr(a + 1);
    size_t d = b.find_last_of('.');
    if (d != std::string::npos) b = b.substr(0, d);
    for (char& c : b) if (!isalnum((unsigned char)c)) c = '_';
    return b;
}

int main(int argc, char** argv) {
    std::string res1, res2;
    std::string cart, expander1, outdir = "out", prefix, dump_path, audio_path;
    std::string audio_trace_path;
    std::string record_path, playback_path, expander_trace_path;
    std::string source_path;
    long source_frame = -1;
    bool source_started = false, source_seen = false, source_done = false;
    bool source_trace = false;
    std::string source_snoop_path;
    unsigned source_snoop_from = 0;
    uint64_t last_source_keys = 0;
    long frames = 300, max_cycles = 2000000000;
    long shot_every = 0, dump_every = 0, trace_cpu = 0, trace_from = 0;
    bool money_trace = false;
    bool progressive = false;
    long joy_trace_from = -1;
    long joy_focus_frame = -1;
    long joy_results_from = -1;
    unsigned joy_return_pc = 0x22be;
    long joy_timer_base = 2580, joy_timer_step = 7;
    bool joy_timer_curve = false;
    bool joy_timer_auto = true;
    struct JoyTimer { long base, step; };
    std::vector<JoyTimer> joy_timer_sweep;
    int  scale = 3, cart_type = 0;
    bool shot_last = false, want_ppm = false, want_ascii = false;
    bool want_ram = false, frame_log = false, quiet = false, probe = false;
    std::set<long> shots, dumps;
    struct Press {
        int bit;
        long from, to, offset = 0, start_cycle = -1, reset_until = -1;
    };
    std::vector<Press> presses;
    struct JoyPress { std::string direction; long from, to; int player; };
    std::vector<JoyPress> joy_presses;
    struct JoyPot { int channel, value; long from, to; };
    std::vector<JoyPot> joy_pots;

    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto need = [&](const char* what) -> const char* {
            if (i + 1 >= argc) { fprintf(stderr, "error: %s needs a value\n", what); exit(1); }
            return argv[++i];
        };
        if      (a == "--help" || a == "-h") { usage(argv[0]); return 0; }
        else if (a == "--res1")        res1 = need("--res1");
        else if (a == "--res2")        res2 = need("--res2");
        else if (a == "--expander1")   expander1 = need("--expander1");
        else if (a == "--record")      record_path = need("--record");
        else if (a == "--playback")    playback_path = need("--playback");
        else if (a == "--expander-trace") expander_trace_path = need("--expander-trace");
        else if (a == "--cart")        cart = need("--cart");
        else if (a == "--source-trace") source_trace = true;
        else if (a == "--source-snoop") source_snoop_path = need("--source-snoop");
        else if (a == "--source-snoop-from") source_snoop_from = strtoul(need("--source-snoop-from"), nullptr, 0);
        else if (a == "--source") {
            std::string value = need("--source");
            size_t at = value.rfind('@');
            if (!source_path.empty() || at == std::string::npos) {
                fprintf(stderr, "error: --source needs one FILE@FRAME\n"); return 1;
            }
            source_path = value.substr(0, at);
            char* end = nullptr;
            source_frame = strtol(value.c_str() + at + 1, &end, 10);
            if (at + 1 == value.size() || *end || source_frame < 0) {
                fprintf(stderr, "error: invalid --source frame\n"); return 1;
            }
        }
        else if (a == "--cart-type")   cart_type = atoi(need("--cart-type"));
        else if (a == "--frames")      frames = atol(need("--frames"));
        else if (a == "--max-cycles")  max_cycles = atol(need("--max-cycles"));
        else if (a == "--240p")        progressive = true;
        else if (a == "--shot")        parse_list(need("--shot"), shots);
        else if (a == "--shot-every")  shot_every = atol(need("--shot-every"));
        else if (a == "--shot-last")   shot_last = true;
        else if (a == "--outdir")      outdir = need("--outdir");
        else if (a == "--prefix")      prefix = need("--prefix");
        else if (a == "--scale")       scale = atoi(need("--scale"));
        else if (a == "--ppm")         want_ppm = true;
        else if (a == "--ascii")       want_ascii = true;
        else if (a == "--dump")        parse_list(need("--dump"), dumps);
        else if (a == "--dump-every")  dump_every = atol(need("--dump-every"));
        else if (a == "--ram")         want_ram = true;
        else if (a == "--dump-file")   dump_path = need("--dump-file");
        else if (a == "--trace-cpu")   trace_cpu = atol(need("--trace-cpu"));
        else if (a == "--trace-from")  trace_from = atol(need("--trace-from"));
        else if (a == "--money-trace") money_trace = true;
        else if (a == "--audio-log")   audio_path = need("--audio-log");
        else if (a == "--audio-trace") audio_trace_path = need("--audio-trace");
        else if (a == "--press") {
            std::string v = need("--press");
            size_t at = v.find('@');
            if (at == std::string::npos) { fprintf(stderr, "error: --press needs KEY@FRAME\n"); return 1; }
            std::string name = v.substr(0, at);
            long from = atol(v.c_str() + at + 1);
            long hold = 8;
            long offset = 0;
            size_t colon = v.find(':', at);
            if (colon != std::string::npos) hold = atol(v.c_str() + colon + 1);
            size_t delay = colon == std::string::npos ? colon : v.find(':', colon + 1);
            if (delay != std::string::npos) {
                char* end = nullptr;
                offset = strtol(v.c_str() + delay + 1, &end, 10);
                if (end == v.c_str() + delay + 1 || *end || offset < 0 || offset >= 228 * 263 * 4) {
                    fprintf(stderr, "error: --press C must be 0..239855 MCLKs\n"); return 1;
                }
            }
            if (from < 0 || hold <= 0) { fprintf(stderr, "error: --press needs F>=0 and H>0\n"); return 1; }
            int bit = key_bit(name);
            if (bit < 0) { fprintf(stderr, "error: unknown key '%s'\n", name.c_str()); return 1; }
            if (bit == 36 && offset) {
                fprintf(stderr, "error: MASTER CONTROL does not support a key-down delay\n"); return 1;
            }
            presses.push_back({ bit, from, from + hold, offset });
        }
        else if (a == "--joy" || a == "--joy2") {
            std::string v = need(a.c_str());
            size_t at = v.find('@');
            if (at == std::string::npos) { fprintf(stderr, "error: --joy needs DIR@FRAME\n"); return 1; }
            std::string direction = v.substr(0, at);
            if (direction != "UP" && direction != "DOWN" && direction != "LEFT" &&
                direction != "RIGHT" && direction != "FIRE") {
                fprintf(stderr, "error: unknown joystick direction '%s'\n", direction.c_str());
                return 1;
            }
            long from = atol(v.c_str() + at + 1);
            long hold = 8;
            size_t colon = v.find(':', at);
            if (colon != std::string::npos) hold = atol(v.c_str() + colon + 1);
            joy_presses.push_back({ direction, from, from + hold, a == "--joy2" ? 1 : 0 });
        }
        else if (a == "--joy-pot") {
            std::string v = need("--joy-pot");
            int channel, value, used = 0;
            long from, hold;
            if (sscanf(v.c_str(), "%d:%d@%ld:%ld%n", &channel, &value, &from, &hold, &used) != 4 ||
                used != int(v.size()) || channel < 0 || channel > 7 ||
                value < 0 || value > 255 || from < 0 || hold <= 0) {
                fprintf(stderr, "error: --joy-pot needs C:V@F:H (C=0..7, V=0..255, F>=0, H>0)\n");
                return 1;
            }
            joy_pots.push_back({channel, value, from, from + hold});
        }
        else if (a == "--frame-log")   frame_log = true;
        else if (a == "--probe")       probe = true;
        else if (a == "--joy-trace")   joy_trace_from = atol(need("--joy-trace"));
        else if (a == "--joy-focus")   joy_focus_frame = atol(need("--joy-focus"));
        else if (a == "--joy-results") joy_results_from = atol(need("--joy-results"));
        else if (a == "--joy-return-pc") joy_return_pc = strtoul(need("--joy-return-pc"), nullptr, 16);
        else if (a == "--joy-timer-base") {
            joy_timer_base = atol(need("--joy-timer-base"));
            joy_timer_auto = false;
        }
        else if (a == "--joy-timer-step") {
            joy_timer_step = atol(need("--joy-timer-step"));
            joy_timer_auto = false;
        }
        else if (a == "--joy-timer-curve") joy_timer_curve = true;
        else if (a == "--joy-timer-sweep") {
            joy_timer_auto = false;
            std::string list = need("--joy-timer-sweep");
            size_t pos = 0;
            while (pos < list.size()) {
                size_t end = list.find(',', pos);
                std::string item = list.substr(pos, end == std::string::npos ? end : end - pos);
                size_t sep = item.find(':');
                if (sep == std::string::npos) { fprintf(stderr, "error: sweep values need base:step pairs\n"); return 1; }
                JoyTimer candidate = { atol(item.substr(0, sep).c_str()), atol(item.substr(sep + 1).c_str()) };
                if (candidate.base < 0 || candidate.step < 0 || candidate.step > 127 ||
                    candidate.base + candidate.step * 255 > 16383) {
                    fprintf(stderr, "error: joystick sweep value outside timer range\n"); return 1;
                }
                joy_timer_sweep.push_back(candidate);
                if (end == std::string::npos) break;
                pos = end + 1;
            }
        }
        else if (a == "--quiet")       quiet = true;
        else { fprintf(stderr, "error: unknown option %s\n", a.c_str()); usage(argv[0]); return 1; }
    }

    if (res1.empty()) {
        fprintf(stderr, "error: --res1 FILE is required; supply --res2 FILE for the full BIOS\n");
        return 1;
    }

    if (joy_timer_curve && !joy_timer_sweep.empty()) {
        fprintf(stderr, "error: curve and sweep are mutually exclusive\n");
        return 1;
    }

    if (prefix.empty()) prefix = basename_noext(cart.empty() ? res1 : cart);
    if (!source_path.empty() && source_frame >= frames) {
        fprintf(stderr, "error: --source frame must be below --frames\n"); return 1;
    }

    FILE* df = stdout;
    if (!dump_path.empty()) {
        df = fopen(dump_path.c_str(), "w");
        if (!df) { fprintf(stderr, "error: cannot write %s\n", dump_path.c_str()); return 2; }
    }

    FILE* af = nullptr;
    if (!audio_path.empty()) {
        af = fopen(audio_path.c_str(), "w");
        if (!af) { fprintf(stderr, "error: cannot write %s\n", audio_path.c_str()); return 2; }
        fprintf(af, "cycle,frame,pc,code,hpos,vpos,cmd,yint,s23,s24,s25,s26,"
                    "irq_cycle,irq_pc,irq_flags,irq_sources,ack_cycle,masked_ticks,stall_ticks,"
                    "masked_pc,service_stall_ticks\n");
    }

    FILE* atf = nullptr;
    if (!audio_trace_path.empty()) {
        atf = fopen(audio_trace_path.c_str(), "w");
        if (!atf) { fprintf(stderr, "error: cannot write %s\n", audio_trace_path.c_str()); return 2; }
        fprintf(atf, "cycle,frame,frame_cycle,keys,reset,pc,hpos,vpos,port_a_n,port_b_n,"
                     "port_b_wr,clock_previous,held_code,stb,code,latch_ok,irq,ack\n");
    }

    FILE* rf = nullptr;
    if (!record_path.empty()) {
        rf = fopen(record_path.c_str(), "w");
        if (!rf) { fprintf(stderr, "error: cannot write %s\n", record_path.c_str()); return 2; }
        fprintf(rf, "cycle,level,enabled\n");
    }
    int last_record_data = -1, last_record_enable = -1;
    std::vector<uint32_t> tape_samples;
    if (!playback_path.empty()) {
        if (expander1.empty()) {
            fprintf(stderr, "error: --playback requires --expander1\n"); return 1;
        }
        tape_samples = read_tape(playback_path);
    }
    size_t tape_index = 0;
    uint32_t tape_remaining = 0;
    unsigned tape_level = 1;
    bool tape_remote = false;
    FILE* ef = nullptr;
    if (!expander_trace_path.empty()) {
        ef = fopen(expander_trace_path.c_str(), "w");
        if (!ef) { fprintf(stderr, "error: cannot write Expander trace\n"); return 2; }
        fprintf(ef, "cycle,pc,host_data_n,host_clock_n,data_n,clock_n,interrupt_n,record,playback,ack,video_irq,joy_irq,pi_b,acc,flags,r0,r1,r2,r3,r4,r5,sreg_wr,sreg_wa,sreg_wd\n");
    }
    unsigned last_expander_pins = ~0u;
    bool last_expander_ack = false, last_expander_write = false;
    FILE* sf = nullptr;
    if (!source_snoop_path.empty()) {
        sf = fopen(source_snoop_path.c_str(), "w");
        if (!sf) { fprintf(stderr, "error: cannot write source snoop\n"); return 2; }
        fprintf(sf, "cycle,frame,event,pos,keys,symbols,pc,pc1,dc0,acc,flags,isar,columns,col8,addr,data,registers\n");
    }
    bool snooping = false;
    uint64_t snoop_keys = 0;
    unsigned snoop_symbols = 0;
    unsigned snoop_ram = ~0u, snoop_reg = ~0u, snoop_read = ~0u, snoop_write = ~0u;

    Verilated::commandArgs(argc, argv);
    top = new Vtop();
    top->playback_data = 1;

    IoctlDriver io;
    io.quiet = quiet;
    io.add(res1, 0);
    if (!res2.empty()) io.add(res2, 1);
    if (!expander1.empty()) io.add(expander1, 3);
    if (!cart.empty()) io.add(cart, 2);

    FrameGrabber fg;

    top->clk_sys = 0;
    top->reset = 1;
    top->progressive = progressive;
    top->ioctl_download = 0; top->ioctl_upload = 0; top->ioctl_wr = 0;
    top->ioctl_addr = 0; top->ioctl_dout = 0; top->ioctl_din = 0; top->ioctl_index = 0;
    top->ps2_key = 0;
    top->kbd_matrix = 0;
    top->joy_fire = 0;
    top->joy_pots = 0x8080808080808080ULL;
    if (joy_timer_base < 0 || joy_timer_step < 0 || joy_timer_step > 127 ||
        joy_timer_base + joy_timer_step * 255 > 16383) {
        fprintf(stderr, "error: joystick timer range must fit 0..16383 MCLK ticks\n");
        return 1;
    }
    top->joy_timer_base = (uint16_t)joy_timer_base;
    top->joy_timer_step = (uint8_t)joy_timer_step;
    top->joy_timer_curve = joy_timer_curve;
    top->joy_timer_auto = joy_timer_auto;
    top->cart_type = (uint8_t)cart_type;
    top->eval();

    long cycles = 0, last_reported = -1;

    long pushes = 0, pops = 0, umireq = 0, dmagrant = 0, lines_started = 0;
    int  max_level = 0, max_state = 0;
    int  state_seen = 0;
    bool decide_logged = false;
    long ext_int_n = 0, int_ack_n = 0, int_req_n = 0, io_wr_n = 0, overrun_n = 0;
    int last_freeze_x = -1, last_freeze_y = -1;
    int last_joy_enable = -1, last_joy_latch = -1, last_joy_out = -1;
    unsigned last_joy_pc = 0xffff;
    long joy_start_cycle = -1;
    int joy_start_pot = 0, joy_start_latch = 0;
    JoyTimer joy_start_timer = { joy_timer_base, joy_timer_step };
    unsigned joy_sweep_index[8] = {};

    struct AudioIrq {
        long cycle = -1, ack = -1, dac = -1, masked = 0, stalled = 0, service_stalled = 0;
        unsigned pc = 0, flags = 0, sources = 0, masked_pc = 0;
    } audio_pending, audio_serviced;
    bool audio_request_l = false, audio_ack_l = false;
    unsigned audio_sources_l = 0;
    long audio_frame = -1, audio_frame_start = 0;
    uint64_t audio_keys = 0;
    bool audio_clock = false, audio_trace_irq = false, audio_trace_ack = false;

    while (fg.frame <= frames && cycles < max_cycles && !Verilated::gotFinish()) {
        if (audio_frame != fg.frame) {
            audio_frame = fg.frame;
            audio_frame_start = cycles;
        }

        if (!source_path.empty() && !source_started && fg.frame >= source_frame && io.finished) {
            source_started = true;
            io.add(source_path, 5);
            io.finished = false;
            printf("[source] frame=%ld download started\n", fg.frame);
        }

        bool master_control = false;
        {
            uint64_t m = 0;
            for (Press& pr : presses) {
                if (pr.bit == 36) {
                    // release reset by mclk count since video is stopped
                    if (pr.reset_until < 0 && fg.frame >= pr.from) {
                        pr.reset_until = cycles + (pr.to - pr.from) * 228 * 263 * 4;
                        printf("[master-control] frame=%ld cycle=%ld release_cycle=%ld\n",
                               fg.frame, cycles, pr.reset_until);
                    }
                    if (cycles < pr.reset_until) master_control = true;
                    if (cycles == pr.reset_until)
                        printf("[master-control] frame=%ld cycle=%ld released\n", fg.frame, cycles);
                } else {
                    if (pr.start_cycle < 0 && fg.frame >= pr.from)
                        pr.start_cycle = cycles + pr.offset;
                    if (pr.start_cycle >= 0 && cycles >= pr.start_cycle && fg.frame < pr.to)
                        m |= (uint64_t)1 << pr.bit;
                }
            }
            top->kbd_matrix = m;
        }
        top->joy_pots = 0x8080808080808080ULL;
        top->joy_fire = 0;
        for (int player = 0; player < 2; player++) {
            bool up = false, down = false, left = false, right = false, fire = false;
            for (const JoyPress& pr : joy_presses) {
                if (pr.player != player) continue;
                if (fg.frame < pr.from || fg.frame >= pr.to) continue;
                if (pr.direction == "UP") up = true;
                if (pr.direction == "DOWN") down = true;
                if (pr.direction == "LEFT") left = true;
                if (pr.direction == "RIGHT") right = true;
                if (pr.direction == "FIRE") fire = true;
            }
            uint8_t x = left == right ? 128 : (right ? 255 : 0);
            uint8_t y = up == down ? 128 : (down ? 255 : 0);
            unsigned shift = player * 16;
            top->joy_pots = (top->joy_pots & ~(0xffffULL << shift)) |
                            ((uint64_t(x) << 8 | y) << shift);
            top->joy_fire |= (fire ? 1 : 0) << player;
        }

        for (const JoyPot& pot : joy_pots) {
            if (fg.frame < pot.from || fg.frame >= pot.to) continue;
            unsigned shift = pot.channel * 8;
            top->joy_pots = (top->joy_pots & ~(0xffULL << shift)) | (uint64_t(pot.value) << shift);
        }

        io.tick();
        top->reset = (((io.active || !io.finished) && top->ioctl_index != 5) || master_control) ? 1 : 0;

        if (!joy_timer_sweep.empty() && CORE(joy_armed) && CORE(joy_enable_l) &&
            CORE(hblank_l) && CORE(key_latch_l)) {
            unsigned latch = CORE(key_latch_l);
            if ((latch & (latch - 1)) == 0) {
                int axis = 0;
                while (((latch >> axis) & 1) == 0) axis++;
                JoyTimer candidate = joy_timer_sweep[joy_sweep_index[axis] % joy_timer_sweep.size()];
                top->joy_timer_base = (uint16_t)candidate.base;
                top->joy_timer_step = (uint8_t)candidate.step;
            }
        }

        bool joy_trace = (joy_trace_from >= 0 && fg.frame >= joy_trace_from) ||
                         (joy_focus_frame >= 0 && fg.frame == joy_focus_frame);
        bool joy_focus = joy_focus_frame >= 0 && fg.frame == joy_focus_frame;
        // uv201 consumes the registered capture request on this clock
        bool joy_capture = joy_trace && CORE(joy_capture_stb);
        unsigned capture_x = CORE(joy_capture_x), capture_y = CORE(joy_capture_y);
        unsigned capture_cmd = UVR(r_cmd);

        if (!tape_samples.empty()) {
            bool remote = top->playback_enable && !top->record_enable && !top->reset;
            if (remote != tape_remote)
                printf("[tape] cycle=%ld %s interval=%zu/%zu\n", cycles,
                       remote ? "start" : "stop", tape_index, tape_samples.size());
            if (!remote) {
                top->playback_data = 1;
            } else {
                if (!tape_remaining) {
                    if (tape_index < tape_samples.size()) {
                        uint32_t sample = tape_samples[tape_index++];
                        tape_level = sample >> 31;
                        tape_remaining = sample & 0x7fffffff;
                    } else tape_level = 1;
                }
                top->playback_data = tape_level;
                if (tape_remaining) tape_remaining--;
            }
            if (top->reset) {
                tape_index = 0;
                tape_remaining = 0;
                tape_level = 1;
            }
            tape_remote = remote;
        }

        // sample write enables before the edge that commits them
        if (sf && source_started) {
            unsigned pos = top->rootp->top__DOT__source_loader__DOT__position;
            uint64_t keys = top->rootp->top__DOT__source_keys;
            unsigned symbols = top->rootp->top__DOT__apl_symbols;
            auto event = [&](const char* kind, unsigned addr, unsigned data) {
                fprintf(sf, "%ld,%ld,%s,%u,%llu,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u",
                        cycles, fg.frame, kind, pos, (unsigned long long)keys, symbols,
                        unsigned(top->rootp->top__DOT__pc0), unsigned(top->rootp->top__DOT__pc1),
                        unsigned(top->rootp->top__DOT__dc0), unsigned(CPU(acc)),
                        unsigned(CPU(iozcs)), unsigned(CPU(visar)), unsigned(CORE(key_latch_l)),
                        unsigned(top->rootp->top__DOT__core__DOT__u_io__DOT__uv_kbd), addr, data);
                fprintf(sf, ",");
                if (!strcmp(kind, "begin") || !strcmp(kind, "key") || !strcmp(kind, "mode"))
                    for (int i = 0; i < 64; i++) fprintf(sf, "%02X", unsigned(CPU(scratch_regs)[i]));
                fprintf(sf, "\n");
            };
            if (!snooping && pos >= source_snoop_from && top->source_busy) {
                snooping = true;
                snoop_keys = keys;
                snoop_symbols = symbols;
                event("begin", 0, 0);
            }
            if (snooping) {
                if (keys != snoop_keys) event("key", 0, 0);
                if (symbols != snoop_symbols) event("mode", 0x0fe2, symbols);
                snoop_keys = keys;
                snoop_symbols = symbols;
                auto strobe = [&](bool enabled, unsigned addr, unsigned data,
                                  unsigned& previous, const char* kind) {
                    unsigned signature = enabled ? (addr << 8) | data : ~0u;
                    if (enabled && signature != previous) event(kind, addr, data);
                    previous = signature;
                };
                strobe(BUS(sys_ram_we) || BUS(cart_ram_we), BUS(a_eff), BUS(bus_wdata), snoop_ram, "ram");
                strobe(CPU(sreg_wr), CPU(sreg_wa), CPU(sreg_wd), snoop_reg, "scratch");
                strobe(CORE(io_rd), CORE(io_addr), CORE(io_rdata), snoop_read, "io-read");
                strobe(CORE(io_wr), CORE(io_addr), CORE(io_wdata), snoop_write, "io-write");
            }
        }

        unsigned audio_a = 0, audio_b = 0, audio_write = 0, audio_held = 0;
        if (atf) {
            audio_a = CORE(po_a_n_l);
            audio_b = CORE(po_b_n_l);
            audio_write = CORE(port1_wr_l);
            audio_held = CORE(audio_code);
        }

        top->clk_sys = 1;
        top->eval();

        if (atf) {
            bool clock = (audio_b & 0x10) != 0;
            bool expected_stb = !top->reset && clock && !audio_clock;
            unsigned expected_code = top->reset ? 0 : expected_stb ? audio_a & 3 : audio_held;
            bool latch_ok = CORE(audio_stb) == expected_stb && CORE(audio_code) == expected_code;
            bool request = CORE(int_req), ack = CORE(int_ack);
            if (cycles == audio_frame_start || top->kbd_matrix != audio_keys ||
                clock != audio_clock || CORE(audio_stb) || !latch_ok ||
                request != audio_trace_irq || ack != audio_trace_ack) {
                // pins are sampled before the edge; latch and irq state after it
                fprintf(atf, "%ld,%ld,%ld,%llu,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",
                        cycles, fg.frame, cycles - audio_frame_start,
                        (unsigned long long)top->kbd_matrix, unsigned(top->reset),
                        unsigned(top->rootp->top__DOT__pc0), unsigned(CORE(hpos)), unsigned(CORE(vpos)),
                        audio_a, audio_b, audio_write, unsigned(audio_clock), audio_held,
                        unsigned(CORE(audio_stb)), unsigned(CORE(audio_code)), unsigned(latch_ok),
                        unsigned(request), unsigned(ack));
            }
            audio_clock = !top->reset && clock;
            audio_keys = top->kbd_matrix;
            audio_trace_irq = request;
            audio_trace_ack = ack;
        }

        if (ef) {
            unsigned pc = top->rootp->top__DOT__pc0;
            unsigned host = (CORE(po_b_n_l) >> 5) & 3;
            unsigned pins = host | CORE(expander_data_n) << 2 |
                            CORE(expander_clock_n) << 3 | CORE(expander_interrupt_n) << 4 |
                            top->record_enable << 5 | top->playback_enable << 6;
            bool ack = CORE(int_ack);
            bool receive_write = CPU(sreg_wr) && CPU(sreg_wa) == 4 &&
                                 pc >= 0x39e3 && pc < 0x3a5a;
            if (pins != last_expander_pins || (ack && !last_expander_ack) ||
                (receive_write && !last_expander_write)) {
                fprintf(ef, "%ld,%04X,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%02X,%02X,%02X,%02X,%02X,%02X,%02X,%02X,%02X,%u,%u,%02X\n", cycles,
                        pc, host & 1, host >> 1,
                        unsigned(CORE(expander_data_n)), unsigned(CORE(expander_clock_n)),
                        unsigned(CORE(expander_interrupt_n)), unsigned(top->record_enable),
                        unsigned(top->playback_enable), unsigned(ack), unsigned(CORE(yint_irq)),
                        unsigned(CORE(joy_int)), unsigned(CORE(pi_b_n_l)),
                        unsigned(CPU(acc)), unsigned(CPU(iozcs)),
                        unsigned(CPU(scratch_regs)[0]), unsigned(CPU(scratch_regs)[1]),
                        unsigned(CPU(scratch_regs)[2]), unsigned(CPU(scratch_regs)[3]),
                        unsigned(CPU(scratch_regs)[4]), unsigned(CPU(scratch_regs)[5]),
                        unsigned(CPU(sreg_wr)), unsigned(CPU(sreg_wa)), unsigned(CPU(sreg_wd)));
                last_expander_pins = pins;
            }
            last_expander_ack = ack;
            last_expander_write = receive_write;
        }

        if (rf && (top->record_data != last_record_data ||
                   top->record_enable != last_record_enable)) {
            fprintf(rf, "%ld,%u,%u\n", cycles,
                    (unsigned)top->record_data, (unsigned)top->record_enable);
            last_record_data = top->record_data;
            last_record_enable = top->record_enable;
        }

        if (source_started) {
            if (source_trace) {
                uint64_t keys = top->rootp->top__DOT__source_keys;
                if (keys && keys != last_source_keys) {
                    printf("[source-key] frame=%ld pos=%u token=%02X keys=%09llX symbols=%u pc=%04X\n",
                           fg.frame, unsigned(top->rootp->top__DOT__source_loader__DOT__position),
                           unsigned(top->rootp->top__DOT__source_loader__DOT__token),
                           (unsigned long long)keys, unsigned(top->rootp->top__DOT__apl_symbols),
                           unsigned(top->rootp->top__DOT__pc0));
                }
                last_source_keys = keys;
            }
            if (top->source_error) {
                if (source_trace)
                    fprintf(stderr, "[source-stop] frame=%ld pos=%u token=%02X state=%u symbols=%u pc=%04X\n",
                            fg.frame, unsigned(top->rootp->top__DOT__source_loader__DOT__position),
                            unsigned(top->rootp->top__DOT__source_loader__DOT__token),
                            unsigned(top->rootp->top__DOT__source_loader__DOT__state),
                            unsigned(top->rootp->top__DOT__apl_symbols), unsigned(top->rootp->top__DOT__pc0));
                fprintf(stderr, "error: RTL rejected keyboard file\n"); return 1;
            }
            if (top->source_busy) source_seen = true;
            if (source_seen && !top->source_busy && !source_done) {
                if (!top->source_complete) {
                    fprintf(stderr, "error: source entry was cancelled\n"); return 1;
                }
                source_done = true;
                printf("[source] frame=%ld entry finished\n", fg.frame);
            }
        }

        if (af) {
            bool request = CORE(int_req), ack = CORE(int_ack);
            unsigned pc = top->rootp->top__DOT__pc0;
            unsigned sources = CORE(yint_irq) | (CORE(joy_int) << 1) |
                               (!CORE(expander_interrupt_n) << 2);
            if (request && !audio_request_l) {
                audio_pending = {};
                audio_pending.cycle = cycles;
                audio_pending.pc = pc;
                audio_pending.flags = CPU(iozcs);
                audio_pending.sources = sources | audio_sources_l;
            }
            if (ack && !audio_ack_l) {
                audio_pending.ack = cycles;
                audio_serviced = audio_pending;
            }
            if (request && audio_pending.cycle >= 0 && audio_pending.ack < 0) {
                if (!(CPU(iozcs) & 0x10)) {
                    if (!audio_pending.masked) audio_pending.masked_pc = pc;
                    ++audio_pending.masked;
                }
                if (CORE(u_uv202__DOT__cpu_stall)) ++audio_pending.stalled;
            }
            if (audio_serviced.ack >= 0 && audio_serviced.dac < 0 &&
                CORE(u_uv202__DOT__cpu_stall)) ++audio_serviced.service_stalled;
            if (CORE(audio_stb)) audio_serviced.dac = cycles;
            audio_request_l = request;
            audio_ack_l = ack;
            audio_sources_l = sources;
        }
        if (af && CORE(audio_stb))
            fprintf(af, "%ld,%ld,%04X,%u,%u,%u,%02X,%u,%02X,%02X,%02X,%02X,"
                        "%ld,%04X,%02X,%u,%ld,%ld,%ld,%04X,%ld\n", cycles, fg.frame,
                    (unsigned)top->rootp->top__DOT__pc0, (unsigned)CORE(audio_code),
                    (unsigned)top->rootp->top__DOT__hpos, (unsigned)top->rootp->top__DOT__vpos,
                    (unsigned)UVR(r_cmd), (unsigned)UVR(r_y_int),
                    (unsigned)CPU(scratch_regs)[0x23], (unsigned)CPU(scratch_regs)[0x24],
                    (unsigned)CPU(scratch_regs)[0x25], (unsigned)CPU(scratch_regs)[0x26],
                    audio_serviced.cycle, audio_serviced.pc, audio_serviced.flags,
                    audio_serviced.sources, audio_serviced.ack,
                    audio_serviced.masked, audio_serviced.stalled, audio_serviced.masked_pc,
                    audio_serviced.service_stalled);

        if (joy_capture)
            printf("[joy-capture] cycle=%llu frame=%ld x=%u y=%u cmd=%02X accepted=%u freeze_x=%u freeze_y=%u\n",
                   (unsigned long long)cycles, fg.frame, capture_x, capture_y,
                   capture_cmd, (capture_cmd >> 1) & 1,
                   (unsigned)UVR(r_freeze_x), (unsigned)UVR(r_freeze_y));

        if (joy_trace || (joy_results_from >= 0 && fg.frame >= joy_results_from)) {
            unsigned pc = top->rootp->top__DOT__pc0;
            if (last_joy_pc == joy_return_pc && pc != last_joy_pc) {
                unsigned latch = CORE(key_latch_l);
                printf("[joy-result] frame=%ld latch=%02X value=%02X freeze_x=%d freeze_y=%d cmd=%02X",
                       fg.frame, (unsigned)CORE(key_latch_l), (unsigned)CPU(acc),
                       (int)UVR(r_freeze_x), (int)UVR(r_freeze_y), (unsigned)UVR(r_cmd));
                if (latch && (latch & (latch - 1)) == 0) {
                    unsigned axis = 0;
                    while ((latch >> axis) != 1) axis++;
                    printf(" bounds=%02X%02X,%02X%02X",
                           (unsigned)SYSRAM[axis * 4], (unsigned)SYSRAM[axis * 4 + 1],
                           (unsigned)SYSRAM[axis * 4 + 2], (unsigned)SYSRAM[axis * 4 + 3]);
                }
                printf("\n");
            }
            if (joy_trace && pc != last_joy_pc &&
                ((joy_focus && joy_return_pc == 0x1fcb && pc >= 0x1eed && pc <= 0x1fcb) ||
                 (joy_focus && pc >= 0x2250 && pc <= 0x22ad) ||
                 (joy_focus && (pc == 0x21cc || pc == 0x21d1 || pc == 0x21d3 ||
                               pc == 0x21e7 || pc == 0x21eb || pc == 0x21f0 || pc == 0x21f1 ||
                               pc == 0x2201 || pc == 0x2211 || pc == 0x221b ||
                               pc == 0x222e || pc == 0x224d || pc == 0x22ad)) ||
                 pc == 0x2203 || pc == 0x2205 || pc == 0x2207 ||
                 pc == 0x220d || pc == 0x2212 || pc == 0x2218 ||
                 pc == 0x2223 || pc == 0x2227 || pc == 0x2229 ||
                 pc == 0x222b || pc == 0x2237 || pc == 0x2239 ||
                 pc == 0x2241 || pc == 0x2244 || pc == 0x2250 ||
                 pc == 0x225b || pc == 0x2262 || pc == 0x228d ||
                 pc == 0x2297 || pc == 0x229f || pc == 0x22a7 || pc == 0x22ab ||
                 (pc >= 0x22bf && pc <= 0x22da))) {
                unsigned dc = top->rootp->top__DOT__dc0;
                printf("[joy-bios] frame=%ld pc=%04X acc=%02X a=%02X b=%02X qu=%02X ql=%02X flags=%02X isar=%02X s=%02X dc=%04X freeze_x=%d freeze_y=%d latch=%02X",
                       fg.frame, pc, (unsigned)CPU(acc),
                       (unsigned)CPU(scratch_regs)[10], (unsigned)CPU(scratch_regs)[11],
                       (unsigned)CPU(scratch_regs)[14], (unsigned)CPU(scratch_regs)[15],
                       (unsigned)CPU(iozcs),
                       (unsigned)CPU(visar),
                       (unsigned)CPU(scratch_regs)[CPU(visar) & 63], dc,
                       (int)UVR(r_freeze_x), (int)UVR(r_freeze_y),
                       (unsigned)CORE(key_latch_l));
                if (joy_focus) {
                    unsigned axis = CPU(scratch_regs)[16];
                    printf(" cycle=%llu h=%u v=%u cmd=%02X axis_or_gain=%u s17=%02X s18=%02X q=%04X operand=%04X",
                           (unsigned long long)cycles,
                           (unsigned)top->rootp->top__DOT__hpos,
                           (unsigned)top->rootp->top__DOT__vpos, (unsigned)UVR(r_cmd),
                           axis, (unsigned)CPU(scratch_regs)[17], (unsigned)CPU(scratch_regs)[18],
                           ((unsigned)CPU(scratch_regs)[14] << 8) | CPU(scratch_regs)[15],
                           ((unsigned)CPU(scratch_regs)[10] << 8) | CPU(scratch_regs)[11]);
                    unsigned latch = CORE(key_latch_l);
                    if (latch && (latch & (latch - 1)) == 0) {
                        axis = 0;
                        while ((latch >> axis) != 1) axis++;
                        printf(" bounds=%02X%02X,%02X%02X",
                               (unsigned)SYSRAM[axis * 4], (unsigned)SYSRAM[axis * 4 + 1],
                               (unsigned)SYSRAM[axis * 4 + 2], (unsigned)SYSRAM[axis * 4 + 3]);
                    }
                }
                if (dc >= 0x0c00 && dc <= 0x0ffc) {
                    unsigned offset = dc - 0x0c00;
                    printf(" table=%02X%02X%02X%02X",
                           (unsigned)SYSRAM[offset], (unsigned)SYSRAM[offset + 1],
                           (unsigned)SYSRAM[offset + 2], (unsigned)SYSRAM[offset + 3]);
                }
                printf("\n");
            }
            last_joy_pc = pc;
        }

        if (joy_trace &&
            ((int)CORE(joy_enable_l) != last_joy_enable ||
             (int)CORE(key_latch_l) != last_joy_latch)) {
            last_joy_enable = CORE(joy_enable_l);
            last_joy_latch = CORE(key_latch_l);
            printf("[joy-control] cycle=%llu frame=%ld pc=%04X enable=%d latch=%02X "
                   "h=%d v=%d out=%d timer=%d\n",
                   (unsigned long long)cycles, fg.frame,
                   (unsigned)top->rootp->top__DOT__pc0, last_joy_enable, last_joy_latch,
                   (int)top->rootp->top__DOT__hpos, (int)top->rootp->top__DOT__vpos,
                   (int)CORE(joy_out), (int)CORE(joy_timer));
        }

        if (joy_trace &&
            (int)CORE(joy_out) != last_joy_out) {
            last_joy_out = CORE(joy_out);
            unsigned pot = 0;
            for (int i = 0; i < 8; i++)
                if ((CORE(key_latch_l) >> i) & 1)
                    pot |= (unsigned)((top->joy_pots >> (i * 8)) & 0xff);
            if (last_joy_out) {
                joy_start_cycle = cycles;
                joy_start_pot = (int)pot;
                joy_start_latch = (int)CORE(key_latch_l);
                joy_start_timer = { (long)top->joy_timer_base, (long)top->joy_timer_step };
                if (joy_timer_auto)
                    joy_start_timer = { (long)CORE(joy_linear_base), (long)CORE(joy_linear_step) };
                if (joy_timer_curve)
                    joy_start_timer = { pot <= 128 ? 1620 + 23 * (long)pot :
                                        4564 + 53 * ((long)pot - 128), 0 };
            } else if (joy_start_cycle >= 0 && !CORE(joy_armed)) {
                printf("[joy-measure] cycle=%llu start_cycle=%ld frame=%ld latch=%02X pot=%d base=%ld step=%ld expected_mclk=%ld elapsed_mclk=%ld\n",
                       (unsigned long long)cycles, joy_start_cycle,
                       fg.frame, joy_start_latch, joy_start_pot,
                       joy_start_timer.base, joy_start_timer.step,
                       joy_start_timer.base + joy_start_timer.step * joy_start_pot + 1,
                       cycles - joy_start_cycle);
                if (!joy_timer_sweep.empty() && joy_start_latch &&
                    (joy_start_latch & (joy_start_latch - 1)) == 0) {
                    int axis = 0;
                    while (((joy_start_latch >> axis) & 1) == 0) axis++;
                    joy_sweep_index[axis]++;
                }
                joy_start_cycle = -1;
            }
            if (!last_joy_out) joy_start_cycle = -1;
            printf("[joy-edge] cycle=%llu frame=%ld pc=%04X enable=%d latch=%02X pot=%u out=%d timer=%d h=%d v=%d freeze_x=%d freeze_y=%d cmd=%02X ext_int=%d joy_int=%d\n",
                   (unsigned long long)cycles, fg.frame,
                   (unsigned)top->rootp->top__DOT__pc0,
                   (int)CORE(joy_enable_l), (unsigned)CORE(key_latch_l), pot,
                   last_joy_out, (int)CORE(joy_timer),
                   (int)top->rootp->top__DOT__hpos,
                   (int)top->rootp->top__DOT__vpos,
                   (int)UVR(r_freeze_x), (int)UVR(r_freeze_y),
                   (unsigned)UVR(r_cmd), (int)CORE(ext_int), (int)CORE(joy_int));
        }

        if (joy_trace &&
            ((int)UVR(r_freeze_x) != last_freeze_x || (int)UVR(r_freeze_y) != last_freeze_y)) {
            last_freeze_x = UVR(r_freeze_x);
            last_freeze_y = UVR(r_freeze_y);
            printf("[joy] cycle=%llu frame=%ld x=%d y=%d latch=%02X cmd=%02X\n",
                   (unsigned long long)cycles, fg.frame,
                   last_freeze_x, last_freeze_y,
                   (unsigned)CORE(key_latch_l), (unsigned)UVR(r_cmd));
        }

        // sample one-clock irq pulses every clock
        if (probe) {
            if (CORE(hblank_rising) && FET(state) != 0) overrun_n++;
            if (CORE(ext_int)) ext_int_n++;
            if (CORE(int_ack)) int_ack_n++;
            if (CORE(int_req)) int_req_n++;
            if (CORE(io_wr)) io_wr_n++;
        }

        if (probe && CORE(brclk_ena)) {
            if (CORE(fifo_wr_en) && CORE(fifo_writable)) pushes++;
            if (CORE(fifo_pop_l)) pops++;
            if (CORE(fetch_umireq)) umireq++;
            if (CORE(dmareq0)) dmagrant++;
            int lvl = top->rootp->top__DOT__fifo_level;
            if (lvl > max_level) max_level = lvl;
            int st = FET(state);
            if (st > max_state) max_state = st;
            state_seen |= (1 << st);
            if (st == 8 && !decide_logged) {
                decide_logged = true;
                int y = ((FET(xy_hi_l) >> 7) << 8) | FET(y_lo_l);
                int height = FET(dy_l) & 0x3f; if (!height) height = 64;
                int width = FET(dx_l) & 0x1f;
                printf("  decide: obj=%d vpos=%d y=%d h=%d w=%d x=%d xdelta=%d "
                       "dy=%02X dx=%02X -> %s\n",
                       (int)FET(entry_i), (int)top->rootp->top__DOT__vpos, y, height,
                       width, (int)FET(x_l), (int)FET(xdelta_l),
                       (unsigned)FET(dy_l), (unsigned)FET(dx_l),
                       (top->rootp->top__DOT__vpos >= y &&
                        top->rootp->top__DOT__vpos < y + height &&
                        width != 0 && FET(x_l) >= FET(xdelta_l)) ? "ACCEPT" : "reject");
            }
            if (CORE(u_uv202__DOT__hblank_falling)) lines_started++;
        }

        if (money_trace && CORE(cpu_ce)) {
            static unsigned last_pc = 0xffff;
            unsigned pc = top->rootp->top__DOT__pc0;
            if (pc != last_pc &&
                (pc == 0x1119 || pc == 0x111e || pc == 0x1140 ||
                 pc == 0x114a || pc == 0x144b || pc == 0x1526 || pc == 0x165b)) {
                printf("[money] frame=%ld PC=%04X R0=%02X R8=%02X A=%02X "
                       "IS=%02X Q=%02X%02X DC0=%04X\n",
                       fg.frame, pc, (unsigned)CPU(scratch_regs)[0],
                       (unsigned)CPU(scratch_regs)[8], (unsigned)CPU(acc),
                       (unsigned)CPU(visar), (unsigned)CPU(scratch_regs)[14],
                       (unsigned)CPU(scratch_regs)[15],
                       (unsigned)top->rootp->top__DOT__dc0);
            }
            last_pc = pc;
        }

        // trace on the cpu enable only: romc moves in between, so sampling
        // every clk would compare against a value the cpu never saw
        if (trace_cpu > 0 && fg.frame >= trace_from && CORE(cpu_ce)) {
            static uint8_t prev_romc = 0xff;
            static uint32_t prev_pc = 0xffff;
            uint8_t romc = (uint8_t)CORE(romc);
            uint32_t pc = top->rootp->top__DOT__pc0;
            if (romc != prev_romc || pc != prev_pc) {
                printf("%08llu  PC0=%04X PC1=%04X DC0=%04X romc=%02X ph=%X acc=%02X "
                       "addr=%04X rd=%d wr=%d req=%d grant=%d rdata=%02X "
                       "cycle=%ld op=%02X flags=%02X j=%02X irq=%d\n",
                       (unsigned long long)main_time, pc,
                       (unsigned)top->rootp->top__DOT__pc1,
                       (unsigned)top->rootp->top__DOT__dc0,
                       romc, (unsigned)CORE(phase), (unsigned)CPU(acc),
                       (unsigned)CORE(ext_addr), (int)CORE(ext_rd), (int)CORE(ext_wr),
                       (int)CORE(ext_req), (int)CORE(ext_grant),
                       (unsigned)CORE(ext_rdata), cycles,
                       (unsigned)CPU(opcode), (unsigned)CPU(iozcs),
                       (unsigned)CPU(scratch_regs)[9], (int)CORE(int_req));
                if (--trace_cpu == 0) printf("[trace-cpu limit reached]\n");
            }
            prev_romc = romc; prev_pc = pc;
        }

        bool boundary = false;
        if (top->ce_pix)
            boundary = fg.clock(top->VGA_VS, top->VGA_HS, top->VGA_DE != 0,
                                (uint8_t)top->rootp->top__DOT__idx_r);

        if (boundary && fg.complete) {
            long f = fg.frame - 1;

            bool do_shot = shots.count(f) || (shot_every && f % shot_every == 0) ||
                           (shot_last && f == frames - 1);
            bool do_dump = dumps.count(f) || (dump_every && f % dump_every == 0);

            if (frame_log)
                printf("frame %6ld  %3dx%-3d  hash %08X  %s\n",
                       f, fg.last_width, fg.last_height, fg.hash(),
                       fg.blank() ? "uniform" : "");

            if (do_shot) {
                std::vector<uint8_t> rgb; int w, h;
                fg.to_rgb(rgb, w, h, scale);
                char name[1024];
                snprintf(name, sizeof(name), "%s/%s_f%05ld.png", outdir.c_str(), prefix.c_str(), f);
                write_png(name, w, h, rgb);
                if (!quiet) fprintf(stderr, "[shot] %s (%dx%d source %dx%d)\n",
                                    name, w, h, fg.last_width, fg.last_height);
                if (want_ppm) {
                    snprintf(name, sizeof(name), "%s/%s_f%05ld.ppm", outdir.c_str(), prefix.c_str(), f);
                    write_ppm(name, w, h, rgb);
                }
                if (want_ascii) {
                    printf("--- frame %ld (%dx%d) ---\n", f, fg.last_width, fg.last_height);
                    fg.to_ascii(stdout);
                }
            }

            if (do_dump) dump_state(df, f, fg, want_ram);

            if (probe) {
                printf("frame %5ld  push=%ld pop=%ld maxstate=%d | "
                       "overrun=%ld extint=%ld req=%ld ack=%ld | "
                       "smi vec=%04X ext_en=%d tmr_en=%d req=%d\n",
                       f, pushes, pops, max_state,
                       overrun_n, ext_int_n, int_req_n, int_ack_n,
                       (unsigned)SMI(vec), (int)SMI(ext_enable),
                       (int)SMI(timer_enable), (int)CORE(int_req));
                ext_int_n = int_ack_n = int_req_n = io_wr_n = overrun_n = 0;
                pushes = pops = umireq = dmagrant = lines_started = 0;
                max_level = max_state = state_seen = 0;
                decide_logged = false;
            }

            if (!quiet && !frame_log && f / 60 != last_reported) {
                last_reported = f / 60;
                fprintf(stderr, "[run] frame %ld/%ld  cycles %ld\n", f, frames, cycles);
            }
        }

        top->clk_sys = 0;
        top->eval();

        main_time++;
        cycles++;
    }

    if (!source_path.empty() && !source_done) {
        fprintf(stderr, "error: simulation ended before source entry completed\n"); return 1;
    }
    printf("\ndone: %ld frames in %ld cycles\n", fg.frame, cycles);
    printf("      last frame %dx%d, hash %08X, %s\n",
           fg.last_width, fg.last_height, fg.hash(),
           fg.blank() ? "UNIFORM (nothing was drawn)" : "has content");
    if (cycles >= max_cycles) printf("      NOTE: stopped on --max-cycles\n");
    if (!fg.complete)         printf("      WARNING: no complete frame was ever captured\n");

    top->final();
    if (df != stdout) fclose(df);
    if (af) fclose(af);
    if (atf) fclose(atf);
    if (rf) fclose(rf);
    if (ef) fclose(ef);
    if (sf) fclose(sf);
    delete top;
    return 0;
}
