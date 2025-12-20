
安装完dpdk后.
## 编译dpdk
```
meson setup builddir -Dc_args="-O0 -g"
meson setup build -Dc_args="-O0 -g" --default-library=static -Dexamples=vdpa --buildtype debug
```

编译ovs
```
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
./configure --with-dpdk=static
CFLAGS="-O0 -g" CXXFLAGS="-O0 -g"  ./configure --with-dpdk=static
```

## 重启ovs
```
/usr/local/share/openvswitch/scripts/ovs-ctl  restart
```
