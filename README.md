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
* 1. Sync Android source
* 2. Copy this file ([gtel3g.xml](https://github.com/gtel3g/local_manifests/blob/lineage-16.0/gtel3g.xml)) to `.repo/local_manifests` (if that folder doesn't exist then "mkdir" it)
* 3. `repo sync` again
* 4. After syncing source and device-specific repo (from step 2), from your source root folder (where you have synced) open Terminal, `cd` to device/samsung/scx30g-common, type `./patch.sh` (this is the quick patching script)
* 5. `cd` to your source root again, type `. build/envsetup.sh && brunch gtel3g`
