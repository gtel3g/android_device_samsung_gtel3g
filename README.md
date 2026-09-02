##Device configuration for Samsung Galaxy Tab E 9.6 SPRD SM-T561 (gtel3g)

=====================================

Basic   | Spec Sheet
-------:|:-------------------------
CPU     | Quad-core 1,3GHz Cortex-A7
CHIPSET | Spreadtrum SC7730SE sc8830
GPU     | Mali-400MP
Memory  | 1.5 GB
Shipped Android Version | Android 4.4.4 with TouchWiz Essence
Storage | 8 GB
MicroSD | Up to 128 GB
Battery | 5000 mAh Li-Ion (removable)
Dimensions | 241.9 x 149.5 x 8.5 mm
Display | 800 x 1280 pixels, 9.6"
Rear Camera  | 5.0 MP
Front Camera | 2.0 MP
Release Date | June 2015

##Building instructions

### What do you need?
* 50GB left of your hard disk space
* Basic skills / knowledge of Linux

### Building steps
* 1. Sync LineageOS 16.0 source.
* 2. Copy `gtel3g.xml` from the gtel3g local manifests repository to `.repo/local_manifests/`.
* 3. Run `repo sync` again.
* 4. From the Android source root, apply the required source patches:
  `device/samsung/gtel3g/apply-patches.sh`
* 5. Set up the build environment:
  `source build/envsetup.sh`
* 6. Select the device:
  `lunch lineage_gtel3g-userdebug`
* 7. Build LineageOS:
  `mka bacon`
