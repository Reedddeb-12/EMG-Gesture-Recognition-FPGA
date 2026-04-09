# 🦾 EMG Gesture Recognition — FPGA-Based Prosthetic Limb Control

> Real-time hand gesture classification from EMG signals using a fully hand-written Verilog RTL pipeline on Xilinx Artix-7.  

---

## What It Does

When a person tries to move their hand, muscles generate tiny electrical signals (EMG). This system captures those signals from 8 forearm electrodes, processes them in hardware, and classifies which of 8 hand gestures was intended — all in **~2 microseconds** at only **64 mW**, making it wearable and suitable for prosthetic limb control.

---

## Key Features

- ⚡ **~2 µs inference latency** — 7,500× faster than cloud, 25× faster than CPU
- 🔋 **64 mW total power** — wearable and battery-friendly
- 🧠 **INT8 quantised neural network** — no floating point hardware needed
- 🔧 **100% hand-written Verilog RTL** — no HLS, no vendor IP blocks
- 📡 **8-channel EMG input** — 12-bit ADC at 2 kHz
- ✅ **90–95% classification accuracy** on NinaPro DB2 dataset

---

## Gestures Recognised

| ID | Gesture     | ID | Gesture    |
|----|-------------|-----|------------|
| 0  | Rest        | 4  | Point      |
| 1  | Fist        | 5  | Peace Sign |
| 2  | Open Hand   | 6  | Thumbs Up  |
| 3  | Pinch       | 7  | Wave       |

---

## Hardware Architecture

```
ADC Input (8 channels, 12-bit)
        │
        ▼
┌──────────────────────┐
│   EMG Preprocessor   │  High-pass filter → Rectification → RMS
└──────────────────────┘
        │  rms_valid
        ▼
┌──────────────────────┐
│  NN Inference Engine │  INT8 weights × features → 24-bit accumulators → ReLU
└──────────────────────┘
        │  nn_valid
        ▼
┌──────────────────────┐
│    Argmax Block      │  Finds highest-scoring class
└──────────────────────┘
        │
  gesture_class[2:0]
```

---

## Repository Structure

```
EMG-Gesture-Recognition-FPGA/
├── src/
│   ├── top_module.v           # Top-level: connects all pipeline stages
│   ├── emg_preprocessor.v    # Stage 1: ADC → INT8 RMS features
│   ├── argmax.v               # Stage 3: finds winning gesture class
│   ├── mac_unit.v             # Multiply-Accumulate building block
│   ├── weight_memory.v        # Block RAM for INT8 weight matrix
│   ├── conv1d_layer.v         # 1D Convolution layer
│   └── dense_layer.v          # Fully-connected dense layer
├── testbench/
│   └── tb_emg_top.v           # Behavioural testbench — 5 gesture scenarios
├── constraints/
│   └── constraints.xdc        # Timing + I/O pin constraints for Artix-7
├── model/
│   └── weights_real_data_init.mem   # INT8 weights trained on NinaPro DB2
├── scripts/
│   └── create_vivado_project.tcl    # Recreates Vivado project from scratch
└── README.md
```

---

## FPGA Results (Post-Implementation)

| Metric               | Value                              |
|----------------------|------------------------------------|
| Target FPGA          | Xilinx Artix-7 xc7a35ticsg324-1L   |
| Clock                | 50 MHz                             |
| Inference Latency    | ~2 µs (~100 clock cycles)          |
| Setup Slack (WNS)    | +4.927 ns ✅                        |
| Slice LUTs           | 36 / 20,800 → **0.17%**            |
| Flip-Flops           | 36 / 41,600 → **0.09%**            |
| Total On-Chip Power  | **64 mW**                          |
| Accuracy             | 90–95% (NinaPro DB2)               |

---

## Comparison

| Method           | Latency     | Power      | Wearable? |
|------------------|-------------|------------|-----------|
| Cloud (REST API) | 100–500 ms  | High       | ❌        |
| CPU (ARM)        | 50–200 ms   | ~500 mW    | ⚠️        |
| GPU              | 2–5 ms      | 150–300 W  | ❌        |
| **This work**    | **~2 µs**   | **64 mW**  | ✅        |

---

## Getting Started

### Requirements
- Vivado 2025.2
- Xilinx Artix-7 board (Arty A7-35T)

### Recreate the Vivado Project

Open Vivado → Tcl Console:

```tcl
cd /path/to/this/repo
source scripts/create_vivado_project.tcl
```

### Run Simulation

In Vivado: **Flow → Run Simulation → Run Behavioral Simulation**

The testbench drives 5 gesture patterns and prints detected `gesture_class` and `latency_cycles` to the console.

### Synthesise and Implement

```
Run Synthesis → Run Implementation → Report Timing → Generate Bitstream
```

---

## ML Model

- **Dataset:** NinaPro DB2 — 40 subjects, 49 gesture classes (8 used)
- **Model:** Lightweight 1D CNN, <100K parameters
- **Quantisation:** Post-training INT8 (PyTorch) — 4× smaller than FP32
- **Training:** Adam, lr=0.001, 50 epochs, CrossEntropyLoss

---

## Future Scope

Scale to 49 gestures · SPI/I²C ADC interface · Full Conv1D in RTL · Low-power ASIC design

---

## License

MIT License — © 2026 Tanisha Phukan, Reeddhijit Deb
