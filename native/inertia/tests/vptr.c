// Virtual pointer driver: "move x y", "finger AXIS VALUE", "stop AXIS", "wheel VALUE", "wait MS"
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "pointer-protocol.h"
static struct zwlr_virtual_pointer_manager_v1 *manager;
static void global(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
  if (!strcmp(i, "zwlr_virtual_pointer_manager_v1")) manager = wl_registry_bind(r, n, &zwlr_virtual_pointer_manager_v1_interface, 2);
}
static void removed(void *d, struct wl_registry *r, uint32_t n) {}
int main(int argc, char **argv) {
  struct wl_display *dpy = wl_display_connect(NULL);
  if (!dpy) return 1;
  struct wl_registry *reg = wl_display_get_registry(dpy);
  const struct wl_registry_listener l = {global, removed};
  wl_registry_add_listener(reg, &l, NULL);
  wl_display_roundtrip(dpy);
  if (!manager) return 3;
  struct zwlr_virtual_pointer_v1 *p = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, NULL);
  char line[128], cmd[32];
  double a, b;
  while (fgets(line, sizeof line, stdin)) {
    if (sscanf(line, "%31s %lf %lf", cmd, &a, &b) < 1) continue;
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    uint32_t t = ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
    if (!strcmp(cmd, "wait")) { usleep((useconds_t)(a * 1000)); continue; }
    if (!strcmp(cmd, "move")) zwlr_virtual_pointer_v1_motion_absolute(p, t, (uint32_t)a, (uint32_t)b, atoi(argv[1]), atoi(argv[2]));
    else if (!strcmp(cmd, "rel")) zwlr_virtual_pointer_v1_motion(p, t, wl_fixed_from_double(a), wl_fixed_from_double(b));
    else if (!strcmp(cmd, "finger")) { zwlr_virtual_pointer_v1_axis(p, t, (uint32_t)a, wl_fixed_from_double(b)); zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_FINGER); }
    else if (!strcmp(cmd, "stop")) { zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_FINGER); zwlr_virtual_pointer_v1_axis_stop(p, t, (uint32_t)a); }
    else if (!strcmp(cmd, "wheel")) { zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_WHEEL); zwlr_virtual_pointer_v1_axis_discrete(p, t, 0, wl_fixed_from_double(a * 15), (int32_t)a); }
    zwlr_virtual_pointer_v1_frame(p);
    wl_display_flush(dpy);
  }
  wl_display_roundtrip(dpy);
  zwlr_virtual_pointer_v1_destroy(p);
  wl_display_roundtrip(dpy);
  return 0;
}
