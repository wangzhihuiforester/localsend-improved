#!/bin/bash
# bundle_linux_libs.sh - Bundle all shared libraries for maximum Linux compatibility
# This script runs inside the Docker build container (Ubuntu 20.04)
# It collects all shared library dependencies and sets RPATH using patchelf

set -e

BUNDLE_DIR="${1:-/app/build/linux/x64/release/bundle}"
LIB_DIR="$BUNDLE_DIR/lib"

echo "============================================"
echo "LocalSend Linux Library Bundler"
echo "============================================"
echo "Bundle dir: $BUNDLE_DIR"
echo ""

# Create lib directory
mkdir -p "$LIB_DIR"

# Verify the main binary exists
if [ ! -f "$BUNDLE_DIR/localsend_app" ]; then
    echo "ERROR: localsend_app not found in $BUNDLE_DIR"
    exit 1
fi

# Step 1: Copy all dependencies of the main binary
echo "=== Step 1: Copying main binary dependencies ==="
ldd "$BUNDLE_DIR/localsend_app" 2>/dev/null | grep "=>" | awk '{print $3}' | sort -u | while read -r lib_path; do
    if [ -n "$lib_path" ] && [ -f "$lib_path" ]; then
        cp -L "$lib_path" "$LIB_DIR/"
        echo "  Copied: $(basename "$lib_path")"
    fi
done

# Step 2: Copy dependencies of all .so files in the bundle root (Flutter engine, Rust lib, etc.)
echo ""
echo "=== Step 2: Copying bundle .so dependencies ==="
find "$BUNDLE_DIR" -maxdepth 1 -name "*.so" | while read -r so_file; do
    echo "  Checking: $(basename "$so_file")"
    ldd "$so_file" 2>/dev/null | grep "=>" | awk '{print $3}' | sort -u | while read -r lib_path; do
        if [ -n "$lib_path" ] && [ -f "$lib_path" ]; then
            lib_name=$(basename "$lib_path")
            if [ ! -f "$LIB_DIR/$lib_name" ]; then
                cp -L "$lib_path" "$LIB_DIR/"
                echo "    Copied: $lib_name"
            fi
        fi
    done
done

# Step 3: Recursively copy dependencies of all bundled .so files
echo ""
echo "=== Step 3: Copying recursive dependencies ==="
for pass in 1 2 3 4 5; do
    echo "  Pass $pass..."
    new_count=0
    find "$LIB_DIR" -name "*.so*" | while read -r so_file; do
        ldd "$so_file" 2>/dev/null | grep "=>" | awk '{print $3}' | sort -u | while read -r lib_path; do
            if [ -n "$lib_path" ] && [ -f "$lib_path" ]; then
                lib_name=$(basename "$lib_path")
                if [ ! -f "$LIB_DIR/$lib_name" ]; then
                    cp -L "$lib_path" "$LIB_DIR/"
                    echo "    Copied: $lib_name"
                fi
            fi
        done
    done
    current_count=$(ls "$LIB_DIR" 2>/dev/null | wc -l)
    echo "    Library count: $current_count"
done

# Step 4: Explicitly copy critical runtime libraries
echo ""
echo "=== Step 4: Copying critical libraries ==="

# libstdc++
for lib in libstdc++.so.6 libstdc++.so; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgcc_s
for lib in libgcc_s.so.1 libgcc_s.so; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgmodule-2.0 (often needed at runtime)
for lib in libgmodule-2.0.so.0 libgmodule-2.0.so; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgio-2.0 (often needed at runtime)
for lib in libgio-2.0.so.0 libgio-2.0.so; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgobject-2.0
for lib in libgobject-2.0.so.0 libgobject-2.0.so; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libglib-2.0
for lib in libglib-2.0.so.0 libglib-2.0.so; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgthread-2.0
for lib in libgthread-2.0.so.0 libgthread-2.0.so; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libpango and related
for lib in libpango-1.0.so.0 libpangocairo-1.0.so.0 libpangoft2-1.0.so.0 libpangoxft-1.0.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libharfbuzz
for lib in libharfbuzz.so.0 libharfbuzz-gobject.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libwayland
for lib in libwayland-client.so.0 libwayland-cursor.so.0 libwayland-egl.so.1; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libxkbcommon
for lib in libxkbcommon.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgdk_pixbuf
for lib in libgdk_pixbuf-2.0.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libcairo
for lib in libcairo.so.2 libcairo-gobject.so.2; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libfontconfig and freetype
for lib in libfontconfig.so.1 libfreetype.so.6; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libatk
for lib in libatk-1.0.so.0 libatk-bridge-2.0.so.0 libatspi.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgtk-3 and libgdk-3
for lib in libgtk-3.so.0 libgdk-3.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libepoxy
for lib in libepoxy.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libfribidi
for lib in libfribidi.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgraphite2
for lib in libgraphite2.so.3; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libnss3 and libnspr4
for lib in libnss3.so libnssutil3.so libnspr4.so libplc4.so libplds4.so libsmime3.so libsoftokn3.so libssl3.so; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libsecret
for lib in libsecret-1.so.0; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libjsoncpp
for lib in libjsoncpp.so.25 libjsoncpp.so.24 libjsoncpp.so.1; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
        break
    fi
done

# libayatana-appindicator3
for lib in libayatana-appindicator3.so.1 libayatana-ido3-0.4.so.0 libdbusmenu-gtk3.so.4 libdbusmenu-glib.so.4; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libcups
for lib in libcups.so.2; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libgbm, libdrm, libEGL, libGL
for lib in libgbm.so.1 libdrm.so.2 libEGL.so.1 libGL.so.1 libGLESv2.so.2; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# X11 libraries
for lib in libX11.so.6 libXcomposite.so.1 libXcursor.so.1 libXdamage.so.1 libXext.so.6 libXfixes.so.3 libXi.so.6 libXinerama.so.1 libXrandr.so.2 libXrender.so.1 libXtst.so.6; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# libdbus
for lib in libdbus-1.so.3; do
    found=$(find /usr/lib /lib -name "$lib" 2>/dev/null | head -1)
    if [ -n "$found" ] && [ ! -f "$LIB_DIR/$lib" ]; then
        cp -L "$found" "$LIB_DIR/"
        echo "  Copied: $lib"
    fi
done

# Step 5: Create symlinks for versioned libraries
echo ""
echo "=== Step 5: Creating symlinks ==="
cd "$LIB_DIR"
for f in *.so.*; do
    [ -f "$f" ] || continue
    # Create .so symlink (e.g., libfoo.so.1.2.3 -> libfoo.so)
    base=$(echo "$f" | sed 's/\.so\..*/\.so/')
    if [ "$base" != "$f" ] && [ ! -e "$base" ]; then
        ln -sf "$f" "$base"
        echo "  Symlink: $base -> $f"
    fi
    # Create major version symlink (e.g., libfoo.so.1.2.3 -> libfoo.so.1)
    major=$(echo "$f" | sed 's/\.so\.\([0-9]*\)\..*/\.so.\1/')
    if [ "$major" != "$f" ] && [ ! -e "$major" ]; then
        ln -sf "$f" "$major"
        echo "  Symlink: $major -> $f"
    fi
done

# Step 6: Set RPATH on all binaries and shared libraries
echo ""
echo "=== Step 6: Setting RPATH ==="

# Set RPATH on the main binary
patchelf --set-rpath '$ORIGIN/lib' "$BUNDLE_DIR/localsend_app" && echo "  Set RPATH on localsend_app" || echo "  WARNING: Failed to set RPATH on localsend_app"

# Set RPATH on all .so files in the bundle root
find "$BUNDLE_DIR" -maxdepth 1 -name "*.so" | while read -r so_file; do
    patchelf --set-rpath '$ORIGIN/lib' "$so_file" && echo "  Set RPATH on $(basename "$so_file")" || true
done

# Set RPATH on all .so files in lib/
find "$LIB_DIR" -name "*.so*" | while read -r so_file; do
    patchelf --set-rpath '$ORIGIN' "$so_file" 2>/dev/null || true
done
echo "  Set RPATH on all lib/ .so files"

# Step 7: Copy gdk-pixbuf loaders and cache
echo ""
echo "=== Step 7: Copying gdk-pixbuf data ==="
PIXBUF_DIR="$BUNDLE_DIR/lib/gdk-pixbuf-2.0/2.10.0/loaders"
mkdir -p "$PIXBUF_DIR"
find /usr/lib -path "*/gdk-pixbuf-2.0/*/loaders/*.so" -exec cp -L {} "$PIXBUF_DIR/" \; 2>/dev/null || true
if [ -f /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache ]; then
    cp /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache "$BUNDLE_DIR/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    echo "  Copied gdk-pixbuf loaders cache"
fi
echo "  gdk-pixbuf loaders: $(ls "$PIXBUF_DIR" 2>/dev/null | wc -l)"

# Step 8: Copy fontconfig configuration
echo ""
echo "=== Step 8: Copying fontconfig ==="
if [ -d /etc/fonts ]; then
    mkdir -p "$BUNDLE_DIR/etc/fonts"
    cp -r /etc/fonts/* "$BUNDLE_DIR/etc/fonts/" 2>/dev/null || true
    echo "  Copied fontconfig"
fi

# Step 9: Summary and verification
echo ""
echo "============================================"
echo "=== Build Summary ==="
echo "============================================"
echo "Total files in bundle:"
find "$BUNDLE_DIR" -type f | wc -l
echo ""
echo "Bundled libraries:"
ls -la "$LIB_DIR/" | head -50
echo ""
echo "Library count: $(ls "$LIB_DIR/"*.so* 2>/dev/null | wc -l)"
echo ""
echo "=== glibc version requirements ==="
readelf -V "$BUNDLE_DIR/localsend_app" 2>/dev/null | grep -E "GLIBC|Name" | head -20
echo ""
echo "=== libstdc++ version requirements ==="
readelf -V "$BUNDLE_DIR/localsend_app" 2>/dev/null | grep -E "GLIBCXX|CXXABI" | head -10
echo ""
echo "=== Verifying no missing dependencies ==="
MISSING=$(ldd "$BUNDLE_DIR/localsend_app" 2>&1 | grep "not found" || true)
if [ -z "$MISSING" ]; then
    echo "All dependencies satisfied!"
else
    echo "WARNING: Missing dependencies:"
    echo "$MISSING"
fi
echo ""
echo "============================================"
echo "Library bundling complete!"
echo "============================================"
