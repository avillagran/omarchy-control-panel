CXX ?= c++
CXXFLAGS ?= -O2
OUT ?= inertia.so
all:
	$(CXX) $(CXXFLAGS) -std=c++23 -shared -fPIC -fno-gnu-unique plugin.cpp -o $(OUT) $$(pkg-config --cflags hyprland pixman-1 libdrm pangocairo libinput libudev wayland-server xkbcommon)
.PHONY: all
