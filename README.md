# BetterCCBrightness

Adds more controls to the expanded brightness module in Control Center: auto-lock,
auto-brightness, reduce white point (with an intensity slider) and a Night Shift
strength slider.

All credit goes to [level3tjg](https://github.com/level3tjg/BetterCCBrightness),
whose implementation I have left intact. The only changes are to packaging,
so the project builds natively for roothide, which did not exist when the upstream
releases were published. level3tjg is welcome to take any of it upstream, no need
to ask.

## Building

Requires [theos](https://theos.dev); roothide packages need the
[roothide fork](https://github.com/roothide/theos). You also need SDKs under
`$THEOS/sdks` from [theos/sdks](https://github.com/theos/sdks), since this tweak
links private frameworks and Apple's own SDKs ship no stubs for them.

```sh
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide   # roothide, iOS 15.0+
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless   # rootless, iOS 15.0+
make package FINALPACKAGE=1                                 # rootful,  iOS 13.0+
```

`SDK_VER` in the Makefile is pinned rather than left at `latest`. `latest` picks
the highest SDK across both `$THEOS/sdks` and Xcode, and Xcode has moved ahead of
theos/sdks, so it now tends to select an Xcode SDK. Those carry no
PrivateFrameworks stubs and the link ends at
`ld: framework 'BackBoardServices' not found`. Set `SDK_VER` to a version you
actually have under `$THEOS/sdks`.

## Note for roothide users

Upstream releases predate roothide, so running them there means converting a
rootless `.deb`. When I tested it, a converted build did not always behave
identically to one compiled for roothide directly; tapping outside the expanded
module to collapse it did not always take effect. Building from source avoids
the conversion step.

That is not a bug in the tweak. Collapsing on an outside tap is stock Control
Center behaviour, and it works correctly on iOS 16.3 with a from-source build
running unmodified upstream logic.

## License

See [LICENSE](LICENSE).
