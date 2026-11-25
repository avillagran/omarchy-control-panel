// Unit checks for the coast curve. Build: c++ -std=c++23 -I src tests/momentum-test.cpp
#include "Momentum.hpp"
#include <cstdio>
#include <cstdlib>

static int failures = 0;
static void check(bool ok, const char* what) {
    std::printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    failures += !ok;
}

static double coast(Momentum m, double* ms = nullptr, double* first = nullptr, double* last = nullptr) {
    double total = 0, t = 0;
    for (int i = 0; i < 200 && m.active; ++i) {
        const double d = m.tick(16);
        if (d != 0) { if (first && t == 0) *first = d; if (last) *last = d; }
        total += d;
        t += 16;
    }
    if (ms) *ms = t;
    return total;
}

int main() {
    Momentum m;
    for (int i = 0; i < 12; ++i) m.sample(8, 8);
    m.release(10);
    check(m.active, "a fast swipe released promptly starts coasting");
    double ms = 0, first = 0, last = 0;
    const double total = coast(m, &ms, &first, &last);
    check(total > 0, "coast keeps the swipe direction");
    check(last < first, "coast slows down");
    check(ms <= 816, "coast ends within 0.8 s");

    Momentum late;
    for (int i = 0; i < 12; ++i) late.sample(8, 8);
    late.release(120);
    check(!late.active, "lifting long after the last movement does not coast");

    Momentum slow;
    slow.sample(0.05, 50);
    slow.release(10);
    check(!slow.active, "a barely moving finger does not coast");

    Momentum flip;
    for (int i = 0; i < 6; ++i) flip.sample(8, 8);
    flip.sample(-8, 8);
    check(flip.velocity < 0, "reversing direction drops the old velocity");

    Momentum bad;
    bad.sample(1.0 / 0.0, 8);
    bad.release(10);
    check(!bad.active && bad.velocity == 0, "non-finite input resets");

    Momentum capped;
    for (int i = 0; i < 12; ++i) capped.sample(10000, 1);
    check(capped.velocity <= 4.0, "velocity is capped");

    Momentum stall;
    for (int i = 0; i < 12; ++i) stall.sample(8, 8);
    stall.release(10);
    check(stall.tick(500) == 0 && !stall.active, "a stalled event loop ends the coast instead of jumping");
    Momentum single;
    single.sample(15, 20);
    single.release(10);
    check(!single.active, "a single event (one wheel notch) does not coast");

    Momentum fastWheel, slowWheel;
    fastWheel.tau = slowWheel.tau = 220;
    for (int i = 0; i < 6; ++i) fastWheel.sample(15, 15, 150);
    for (int i = 0; i < 6; ++i) slowWheel.sample(15, 120, 150);
    check(fastWheel.velocity > 0.25 && slowWheel.velocity < 0.25, "wheel velocity tells a fast spin from a slow one");
    fastWheel.release(60);
    Momentum touch = fastWheel;
    touch.tau = 140;
    check(coast(fastWheel) > coast(touch), "a longer tau carries further");
    Momentum shortCoast = fastWheel;
    double shortMs = 0, t = 0;
    while (shortCoast.active && t < 3000) { shortCoast.tick(16, 200); t += 16; }
    shortMs = t;
    check(shortMs <= 216, "maxAge bounds how long a coast runs");
    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
