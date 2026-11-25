#pragma once
#include <algorithm>
#include <cmath>

// Velocity is in axis units/ms. Decay integrates elapsed time, not frame count.
// `tau` sets how far a coast carries: it covers velocity * tau units in total.
struct Momentum {
    double velocity = 0;
    double age = 0;
    double tau = 140;
    int samples = 0;
    bool active = false;
    void reset() { velocity = age = 0; samples = 0; active = false; }
    // maxDt bounds the gap a velocity is measured over: touchpads report every
    // few ms, wheel notches arrive up to ~150 ms apart.
    void sample(double delta, double dt, double maxDt = 50.0) {
        if (!std::isfinite(delta) || !std::isfinite(dt)) { reset(); return; }
        active = false;
        age = 0;
        const double next = std::clamp(delta / std::clamp(dt, 4.0, maxDt), -4.0, 4.0);
        velocity = velocity * next < 0 ? next : velocity * 0.5 + next * 0.5;
        ++samples;
    }
    // One lone event (a single wheel notch, a touch) never coasts.
    void release(double idle) { active = samples >= 2 && idle < 80 && std::abs(velocity) >= 0.02; }
    // maxAge is the longest a coast may run, in ms.
    double tick(double dt, double maxAge = 800) {
        if (!active || !std::isfinite(dt) || dt <= 0 || dt > 100 || age + dt > maxAge) { reset(); return 0; }
        const double decay = std::exp(-dt / tau);
        const double delta = velocity * tau * (1.0 - decay);
        velocity *= decay;
        age += dt;
        if (std::abs(velocity) < 0.02) active = false;
        return delta;
    }
};
