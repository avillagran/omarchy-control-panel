// Minimal Wayland client: a solid xdg_toplevel that logs every wl_pointer axis event.
#define _GNU_SOURCE
#include <wayland-client.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include "xdg-shell-protocol.h"

static struct wl_compositor *comp;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct xdg_wm_base *wm;
static struct wl_surface *surf;
static int width = 800, height = 600, configured;

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}
static void out(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  printf("%.1f ", now_ms());
  vprintf(fmt, ap);
  va_end(ap);
  fflush(stdout);
}

static void p_enter(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *sf, wl_fixed_t x, wl_fixed_t y) { out("enter\n"); }
static void p_leave(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *sf) { out("leave\n"); }
static void p_motion(void *d, struct wl_pointer *p, uint32_t t, wl_fixed_t x, wl_fixed_t y) {}
static void p_button(void *d, struct wl_pointer *p, uint32_t s, uint32_t t, uint32_t b, uint32_t st) {}
static void p_axis(void *d, struct wl_pointer *p, uint32_t t, uint32_t a, wl_fixed_t v) { out("axis %u %.3f t=%u\n", a, wl_fixed_to_double(v), t); }
static void p_frame(void *d, struct wl_pointer *p) {}
static void p_source(void *d, struct wl_pointer *p, uint32_t s) { out("source %u\n", s); }
static void p_stop(void *d, struct wl_pointer *p, uint32_t t, uint32_t a) { out("stop %u\n", a); }
static void p_discrete(void *d, struct wl_pointer *p, uint32_t a, int32_t v) {}
static void p_v120(void *d, struct wl_pointer *p, uint32_t a, int32_t v) {}
static void p_dir(void *d, struct wl_pointer *p, uint32_t a, uint32_t dir) {}
static const struct wl_pointer_listener pl = {p_enter, p_leave, p_motion, p_button, p_axis, p_frame, p_source, p_stop, p_discrete, p_v120, p_dir};

static void ping(void *d, struct xdg_wm_base *w, uint32_t s) { xdg_wm_base_pong(w, s); }
static const struct xdg_wm_base_listener wml = {ping};

static void global(void *d, struct wl_registry *r, uint32_t n, const char *i, uint32_t v) {
  if (!strcmp(i, "wl_compositor")) comp = wl_registry_bind(r, n, &wl_compositor_interface, 4);
  else if (!strcmp(i, "wl_shm")) shm = wl_registry_bind(r, n, &wl_shm_interface, 1);
  else if (!strcmp(i, "wl_seat")) seat = wl_registry_bind(r, n, &wl_seat_interface, v < 9 ? v : 9);
  else if (!strcmp(i, "xdg_wm_base")) { wm = wl_registry_bind(r, n, &xdg_wm_base_interface, 1); xdg_wm_base_add_listener(wm, &wml, NULL); }
}
static void gremove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener rl = {global, gremove};

static void draw(void) {
  int stride = width * 4, size = stride * height;
  int fd = memfd_create("probe", 0);
  ftruncate(fd, size);
  uint32_t *px = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  for (int i = 0; i < width * height; i++) px[i] = 0xff3060a0;
  struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
  struct wl_buffer *buf = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_XRGB8888);
  wl_shm_pool_destroy(pool);
  munmap(px, size);
  close(fd);
  wl_surface_attach(surf, buf, 0, 0);
  wl_surface_damage(surf, 0, 0, width, height);
  wl_surface_commit(surf);
}
static void xs_conf(void *d, struct xdg_surface *xs, uint32_t s) { xdg_surface_ack_configure(xs, s); draw(); configured = 1; }
static const struct xdg_surface_listener xsl = {xs_conf};
static void tl_conf(void *d, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *st) { if (w > 0 && h > 0) { width = w; height = h; } }
static void tl_close(void *d, struct xdg_toplevel *t) { exit(0); }
static void tl_bounds(void *d, struct xdg_toplevel *t, int32_t w, int32_t h) {}
static void tl_caps(void *d, struct xdg_toplevel *t, struct wl_array *c) {}
static const struct xdg_toplevel_listener tll = {tl_conf, tl_close, tl_bounds, tl_caps};

int main(int argc, char **argv) {
  struct wl_display *dpy = wl_display_connect(NULL);
  if (!dpy) return 1;
  struct wl_registry *reg = wl_display_get_registry(dpy);
  wl_registry_add_listener(reg, &rl, NULL);
  wl_display_roundtrip(dpy);
  if (!comp || !shm || !seat || !wm) return 2;
  wl_pointer_add_listener(wl_seat_get_pointer(seat), &pl, NULL);
  surf = wl_compositor_create_surface(comp);
  struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(wm, surf);
  xdg_surface_add_listener(xs, &xsl, NULL);
  struct xdg_toplevel *tl = xdg_surface_get_toplevel(xs);
  xdg_toplevel_add_listener(tl, &tll, NULL);
  xdg_toplevel_set_app_id(tl, argc > 1 ? argv[1] : "inertia-probe");
  xdg_toplevel_set_title(tl, "inertia probe");
  wl_surface_commit(surf);
  while (wl_display_dispatch(dpy) != -1) {}
  return 0;
}
