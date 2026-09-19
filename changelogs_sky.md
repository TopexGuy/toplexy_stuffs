Date: 18/09/2026
Device changelogs:
- Updated blobs & fingerprints to OS2.0.210.0.VMWMIXM (30/08)
- Added TopexTool in Parts (30/08)
- Fixed grip sensor & add wcnssr on boot (27/08)
- Disabled VINTF kernel version enforcement (24/08)
- Added GNSS AIDL v1 to framework matrix (21/08)
- Imported activity open/close animations (16/08)
- Enabled BBR congestion control with FQ qdisc (16/08)
- Removed duplicate frequency step (15/08)
- Imported task profiles (23/07)
- ZRAM switched to ZSTD + fixed swappiness override (21/07)
- Fixed powerhint GPU defaults & big cluster interaction min freq (25/07)
- Wired up post_boot & deduplicated memory tuning (22/07)
- Set product shipping API level to 33 (20/07)
- And Many More...

Kernel changelogs:
- Upstream 5.10.269 Kernel (02/09)
- Merged LineageOS sm8450 into 17 (11/09)
- Disabled PANIC_ON_OOPS (18/09)
- NT36672C touch: gesture read sync & suspend decouple fixes (03/09)
- Added xiaomi_touch up_threshold/tolerance sysfs bridge (03/09)
- Fixed ufs_cpufreq_status for merged config (06/09)
- Added IPC support to defconfig (30/08)
- Fixed minidump WALT task accessor (05/09)
- Fixed camera-kernel memleak issues (02/09)
- Updated aw87xxx audio-kernel module (16/08)
- And More...


---


Date: 19/07/2026
Device changelogs:
- qca_cld3 as Wifi Driver
- raised powerhint INTERACTION min frequencies
- enabled sparse images
- enabled sustained performance
- overrided cpufreq governor 
- disabled rcu expedited 
- firmware included
- And Many More...

Kernel changelogs:
- Upstream 5.10.257 Kernel
- integrated Backend MGLRU (Disabled in Boot)
- pre-Root KSUN Dropped (Use LKM)
- reduced IPI overhead
- Fixed Reboot Panic/Bug
- And More...


---


Date: 29/06/2026
Device changelogs:
- Clean Rebased DeviceTree
- firmware integrated
- Added Dynamic Swappiness System
- Now arm64-v8a, armeabi-v7a, armeabi Supported 
- Enabled HID Device Profile
- Implimented Background App Limit 
- Dynamic Dalvik Heap Implimented
- And Many More...

Kernel changelogs:
- Merged ASB-2026-06-01_12-5.10
- Upstream 5.10.255 
- Dropped MGLRU Initial Stub
- KSUN Patched
- Enabled WALT scheduler and TEO idle governor
- Enabled BBR congestion control and FQ scheduler
- Tuned mem_offline alignment for 6GB density
- And More...


---


Date: 30/04/2026
Device changelogs:
- Added Dolby + BCR
- dropped firmware integration
- Added Debloater
- Reverted config_screenBrightnessDoze to float conversion
- Haptics Inhacement

Kernel changelogs:
- added mglru initial implimentation 
- patched ksun
- Added CONFIG_HZ value to 100
- Disabled CONFIG_NTFS_DEBUG
- Removed CONFIG_ZRAM_WRITEBACK & CONFIG_ZRAM_WRITEBACK
