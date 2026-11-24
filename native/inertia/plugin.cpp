// Scroll inertia for Omarchy. After the fingers lift off the touchpad (or,
// when enabled, after a mouse wheel stops spinning), keep sending the focused
// surface scroll frames that slow down, for at most 0.8 s.
// It only listens to Hyprland's input events: no function hooks, and nothing
// is sent when no surface has pointer focus.
//
// Options (reset to these defaults on every config reload):
//   plugin:inertia:touchpad  true   coast after a two-finger touchpad scroll
//   plugin:inertia:mouse     false  coast after a fast mouse-wheel spin
#include "Momentum.hpp"
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/version.h>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <array>
#include <chrono>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
std::array<Momentum, 2> axes;
std::array<Clock::time_point, 2> sampled;
Clock::time_point tickTime;
wl_event_source* timer = nullptr;
// A wheel reports no "stopped" event: silence this long after the last notch
// is the release.
constexpr int WHEEL_RELEASE_MS = 60;
// Slower than this (about a notch every 60 ms) a wheel just stops, as it does
// without inertia, so careful scrolling stays exact.
constexpr double WHEEL_MIN_VELOCITY = 0.25;
constexpr double TOUCHPAD_TAU = 140;
constexpr double WHEEL_TAU = 220;
wl_event_source* wheelTimer = nullptr;
unsigned wheelAxis = 0;
SP<Config::Values::CBoolValue> touchpadOption;
SP<Config::Values::CBoolValue> mouseOption;
enum class Source { None, Finger, Wheel };
Source source = Source::None;
WP<CWLSurfaceResource> target;
std::vector<Hyprutils::Signal::CHyprSignalListener> listeners;

double elapsed(Clock::time_point now, Clock::time_point then) {
    return std::chrono::duration<double, std::milli>(now - then).count();
}
void stop() {
    for (auto& axis : axes) axis.reset();
    target.reset();
    source = Source::None;
    if (timer) wl_event_source_timer_update(timer, 0);
    if (wheelTimer) wl_event_source_timer_update(wheelTimer, 0);
}
bool coasting() { return axes[0].active || axes[1].active; }
void startCoast(Clock::time_point now) {
    tickTime = now;
    wl_event_source_timer_update(timer, 16);
}
bool allowed() {
    // Keep native inertia in browsers and terminals; never emit without a target.
    const auto surface = g_pSeatManager->m_state.pointerFocus.lock();
    if (!surface) return false;
    // The window under the pointer, even when it opened under a still cursor.
    // Popups and subsurfaces fall back to the last window the mouse focused.
    const auto hl = Desktop::View::CWLSurface::fromResource(surface);
    auto window = hl ? Desktop::View::CWindow::fromView(hl->view()) : nullptr;
    if (!window) window = g_pInputManager->m_lastMouseFocus.lock();
    if (!window) return false;
    std::string cls = window->metadata().appID();
    std::transform(cls.begin(), cls.end(), cls.begin(), [](unsigned char c) { return std::tolower(c); });
    for (const auto* excluded : {"firefox", "chrom", "brave", "vivaldi", "librewolf", "zen", "kitty", "alacritty", "foot", "ghostty", "terminal"})
        if (cls.find(excluded) != std::string::npos) return false;
    return true;
}
int tick(void*) {
    if (!allowed() || target.expired() || target.lock() != g_pSeatManager->m_state.pointerFocus.lock()) { stop(); return 0; }
    const auto now = Clock::now();
    const auto dt = elapsed(now, tickTime);
    tickTime = now;
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
    bool active = false;
    static auto touchpadFactor = CConfigValue<Config::FLOAT>("input:touchpad:scroll_factor");
    static auto mouseFactor = CConfigValue<Config::FLOAT>("input:scroll_factor");
    const bool wheel = source == Source::Wheel;
    // Wheel coasting goes out as continuous scrolling: smooth frames, no notches.
    const auto axisSource = wheel ? WL_POINTER_AXIS_SOURCE_CONTINUOUS : WL_POINTER_AXIS_SOURCE_FINGER;
    const double factor = wheel ? *mouseFactor : *touchpadFactor;
    for (unsigned i = 0; i < 2; ++i) {
        const auto delta = axes[i].tick(dt);
        if (delta != 0)
            g_pSeatManager->sendPointerAxis(ms, static_cast<wl_pointer_axis>(i), delta * factor, 0, 0,
                axisSource, WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL);
        active |= axes[i].active;
    }
    g_pSeatManager->sendPointerFrame();
    if (active) wl_event_source_timer_update(timer, 16);
    else source = Source::None;
    return 0;
}
int wheelReleased(void*) {
    if (source != Source::Wheel || !allowed() || target.expired() || target.lock() != g_pSeatManager->m_state.pointerFocus.lock()) { stop(); return 0; }
    const auto now = Clock::now();
    auto& axis = axes[wheelAxis];
    axis.release(elapsed(now, sampled[wheelAxis]));
    if (axis.active && std::abs(axis.velocity) >= WHEEL_MIN_VELOCITY) startCoast(now);
    else stop();
    return 0;
}
void wheelAxisEvent(const IPointer::SAxisEvent& e, unsigned i) {
    auto current = g_pSeatManager->m_state.pointerFocus;
    const auto now = Clock::now();
    const auto dt = elapsed(now, sampled[i]);
    // A new notch takes over from a coast; reversing direction cancels it.
    const bool reversed = coasting() && axes[i].velocity * e.delta < 0;
    if (source != Source::Wheel || target.lock() != current.lock() || reversed || i != wheelAxis) stop();
    else if (coasting()) {
        for (auto& axis : axes) axis.active = false;
        wl_event_source_timer_update(timer, 0);
    }
    source = Source::Wheel;
    target = current;
    wheelAxis = i;
    if (dt > 150) axes[i].reset();
    axes[i].tau = WHEEL_TAU;
    axes[i].sample(e.delta, dt, 150);
    sampled[i] = now;
    wl_event_source_timer_update(wheelTimer, WHEEL_RELEASE_MS);
}
void axis(const IPointer::SAxisEvent& e, Event::SCallbackInfo& info) {
    const unsigned i = static_cast<unsigned>(e.axis);
    if (info.cancelled || i > 1 || !std::isfinite(e.delta) || !allowed()) { stop(); return; }
    if (e.source == WL_POINTER_AXIS_SOURCE_WHEEL) {
        if (mouseOption && mouseOption->value() && e.delta != 0) wheelAxisEvent(e, i);
        else stop();
        return;
    }
    if (e.source != WL_POINTER_AXIS_SOURCE_FINGER || !touchpadOption || !touchpadOption->value()) { stop(); return; }
    auto current = g_pSeatManager->m_state.pointerFocus;
    if (source != Source::Finger || target.lock() != current.lock()) stop();
    source = Source::Finger;
    target = current;
    const auto now = Clock::now();
    const auto dt = elapsed(now, sampled[i]);
    if (e.delta == 0) {
        // Only an explicit finger axis-stop starts momentum. Silence never does.
        axes[i].release(dt);
        if (axes[i].active) startCoast(now);
    } else {
        if (coasting()) stop();
        source = Source::Finger;
        target = current;
        if (dt > 80) axes[i].reset();
        axes[i].tau = TOUCHPAD_TAU;
        axes[i].sample(e.delta, dt);
        sampled[i] = now;
    }
}
}
APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    // Check before registering callbacks. The loader also checks the API ABI.
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("omarchy-inertia: incompatible Hyprland ABI");
    timer = wl_event_loop_add_timer(g_pCompositor->m_wlEventLoop, tick, nullptr);
    wheelTimer = wl_event_loop_add_timer(g_pCompositor->m_wlEventLoop, wheelReleased, nullptr);
    if (!timer || !wheelTimer) throw std::runtime_error("omarchy-inertia: timer unavailable");
    touchpadOption = makeShared<Config::Values::CBoolValue>("plugin:inertia:touchpad", "Keep scrolling briefly after the fingers lift off the touchpad", true);
    mouseOption = makeShared<Config::Values::CBoolValue>("plugin:inertia:mouse", "Keep scrolling briefly after a fast mouse-wheel spin", false);
    HyprlandAPI::addConfigValueV2(handle, touchpadOption);
    HyprlandAPI::addConfigValueV2(handle, mouseOption);
    listeners.emplace_back(Event::bus()->m_events.input.mouse.axis.listen(axis));
    // Moving a mouse while its wheel coasts is normal; only touchpad coasts stop.
    listeners.emplace_back(Event::bus()->m_events.input.mouse.move.listen([](const Vector2D&, Event::SCallbackInfo&) {
        if (source != Source::Wheel) stop();
    }));
    listeners.emplace_back(Event::bus()->m_events.input.mouse.button.listen([](const IPointer::SButtonEvent&, Event::SCallbackInfo&) { stop(); }));
    listeners.emplace_back(Event::bus()->m_events.input.keyboard.key.listen([](const IKeyboard::SKeyEvent&, Event::SCallbackInfo&) { stop(); }));
    listeners.emplace_back(Event::bus()->m_events.window.active.listen([] { stop(); }));
    // Contact/hold cancels coasting even without a click or new scroll.
    for (const auto& pointer : g_pInputManager->m_pointers) {
        if (!pointer || !pointer->m_isTouchpad) continue;
        listeners.emplace_back(pointer->m_pointerEvents.holdBegin.listen([](const IPointer::SHoldBeginEvent&) { stop(); }));
        listeners.emplace_back(pointer->m_pointerEvents.motion.listen([](const IPointer::SMotionEvent&) { stop(); }));
    }
    // A config read before this load could not set plugin:inertia:*; read it again.
    HyprlandAPI::reloadConfig();
    return {"omarchy-inertia", "Scroll inertia for Omarchy", "avillagran", "0.1.1"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    listeners.clear();
    stop();
    if (timer) wl_event_source_remove(timer);
    if (wheelTimer) wl_event_source_remove(wheelTimer);
    timer = wheelTimer = nullptr;
    touchpadOption.reset();
    mouseOption.reset();
}
