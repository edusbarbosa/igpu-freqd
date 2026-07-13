# igpu-freqd

[🇧🇷 Leia isso em português](README.pt-br.md)

This is a userspace daemon written in Bash that dynamically manages the frequency of the Intel integrated GPU (iGPU) through the kernel's sysfs. Rather than locking the frequency to a fixed value, it continuously adjusts the minimum allowable frequency (gt_min_freq_mhz) based on the workload and temperature of the package, balancing performance and heat.

## Why does this exist?

I created this tool because my Acer laptop, with integrated Intel HD Graphics, was performing extremely poorly (less than 100 FPS) in light games like Counter-Strike 1.6. I was using Windows and decided to migrate to Nobara Linux (7.1.3-200.nobara.fc44.x86_64
) to see if anything would change. To my surprise, the poor performance continued there as well. By taking the time to study the GPU clock and temperature, I found that some OEMs apparently do not handle automatic GPU boosting well in games, even when the temperature is normal. In my case, the clock was stuck at 300 MHz. With no other alternative, I dedicated a few days to this project, which fortunately solved the problem! The FPS became high, the temperature remained stable, with no stuttering or excessive latency.

## How it works?

The script uses several parameters (polling rate, temperature limits, hysteresis, smoothing factors, etc.) that have values set by default and are customizable by the file located at /etc/igpu-freqd.conf. It then takes the data from the hardware and automatically adjusts some dependent parameters that will be used in calculating the frequency. The code reads the temperature sensor file, converts it to degrees Celsius, and applies an Exponential Moving Average (EMA) Filter to smooth out sudden temperature spikes, as well as uses the percentage of load applied to the GPU to calculate the optimal minimum frequency.

To make it robust to failures in load measurement (which are not done in real time, but every 0.2s to reduce computational cost), the daemon keeps the history of the last 5 readings. If there are 3 consecutive 0% reads, the GPU is considered idle; otherwise, the last reliable read value is used.

## Core

The daemon's core converts load and temperature into a target frequency through two main steps.

### Load Mapping

GPU load ($L$, in %) is mapped to a frequency $f_{load}$ using a logarithmic scale, which allows for high responsiveness at low loads and smooth saturation at high loads:

$$f_{load} = f_{base} + \frac{f_{max} - f_{base}}{\ln(101)} \cdot \ln(L + 1)$$

where $f_{base}$ and $f_{max}$ are the minimum and maximum frequencies supported by the GPU.

### Thermal Compensation

If the measured temperature ($T$) exceeds the set threshold ($T_{limit}$), the frequency is attenuated exponentially to prioritize cooling:

$$f_{final} = f_{base} + (f_{load} - f_{base}) \cdot e^{-\alpha \cdot (T - T_{limit})}$$

where $\alpha$ is the thermal decay factor (`THERMAL_DECAY_FACTOR`). If $T \leq T_{limit}$, then $f_{final} = f_{load}$.

### Stability Filters

Finally, before it is applied, two mechanisms prevent oscillations: **hysteresis**, which makes the new frequency apply only if the absolute difference relative to the current one exceeds the defined threshold ($H$), and **slew rate**, which limits the maximum variation per cycle to $S$ MHz, promoting less abrupt clock transitions.

## Installation

Run the installer directly from the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/edusbarbosa/igpu-freqd/main/install.sh | sudo bash
```

## Settings

| Parameter | Default value | Description |
|-----------|---------------|-------------|
| `POLL_RATE` | `0.4` | Interval, in seconds, to read the GPU load. |
| `TEMP_LIMIT_C` | `90` | Temperature limit, in degrees Celsius, applied in the thermal compensation calculation. |
| `HYSTERESIS` | `30` | Minimum threshold, in MHz, that the current clock must differ from the new target frequency by to apply the change. |
| `INTEL_GPU_TOP_TIMEOUT` | `0.3` | Maximum waiting time, in seconds, to read the `intel_gpu_top` command before aborting (`timeout`). |
| `INTEL_GPU_TOP_SAMPLES` | `100` | Number of samples collected by `intel_gpu_top` while reading to determine GPU usage. |
| `FALLBACK_FREQ_MHZ` | `800` | Safety frequency, in MHz, applied if the script repeatedly fails while trying to read the card load. |
| `FALLBACK_TEMP_C` | `40` | Temperature threshold, in degrees Celsius, used as a fallback limit when the script cannot read the card load and needs to prevent overheating. |
| `MAX_FAILURES` | `3` | Maximum number of consecutive read failures tolerated before triggering the fallback. |
| `SMOOTHING_WINDOW` | `5` | Window size (number of cycles) used to calculate the moving average of the GPU load, ignoring short unreal peaks. |
| `ALPHA_TEMP` | `0.3` | Smoothing factor (from 0 to 1) of the temperature exponential moving average, preventing the script from reacting to sudden sensor oscillations. |
| `SLEW_RATE_LIMIT` | `100` | Maximum limit, in MHz, that the clock can increase or decrease in a single cycle, forcing smooth acceleration/deceleration. |
| `THERMAL_DECAY_FACTOR` | `0.05` | Multiplier factor of the exponential formula, which defines the aggressiveness of the clock cutoff when the temperature limit is exceeded. |
| `LOG_LEVEL` | `0` | Detail level of the logs sent to `journalctl` (`0` for change-only logs, `1` for heartbeat summaries, `2` for full debug). |
| `HEARTBEAT_CYCLES` | `10` | Number of consecutive cycles without clock changes required to emit a "heartbeat" log showing that the script has not crashed. |

## Uninstall

If you wish to completely remove 'igpu-freqd' and all of its system configuration files, run the following commands:

```bash
sudo systemctl disable --now igpu-freqd.service
sudo rm -f /etc/systemd/system/igpu-freqd.service
sudo rm -f /usr/local/bin/igpu-freqd
sudo rm -f /etc/igpu-freqd.conf
sudo systemctl daemon-reload
```

## Contributing

Contributions are always very welcome! If you've found a bug, have any ideas to improve or optimize the code, feel free to collaborate!
