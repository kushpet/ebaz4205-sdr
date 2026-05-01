# EBAZ4205 SDR — Plan & Repository Structure

## Решение: Bare Metal + FreeRTOS

**Выбор обоснован** следующим образом:

| Критерий | Bare Metal + FreeRTOS | Embedded Linux |
|---|---|---|
| Латентность DMA | ~5 мкс инициализация | ~5.68 мкс + OS overhead |
| DMA throughput (малые блоки) | ~20% от max | ~7% от max |
| Детерминированность | Гарантирована | Нет (планировщик) |
| Сетевой стек | lwIP (входит в Vitis BSP) | Полный стек ядра |
| Время загрузки | 1–2 с | ~30 с |
| Порт cm256cc FEC | Чистый C, портируется | Готов без изменений |
| Отладка | UART + ILA | SSH + gdb |
| Обслуживание | Не требуется | Обновления ядра |

Ключевой факт: на EBAZ4205 нет внешнего кварца PL — тактирование через **FCLK_CLK0** (50 или 100 МГц) из PS PLL.
FCLK_CLK3 (25 МГц) обязательно выводить на пин U18 для тактирования IP101G.

---

## Структура репозитория

```
ebaz4205-sdr/
├── README.md
├── hardware/                        # Vivado 2022.2
│   ├── constraints/
│   │   └── ebaz4205.xdc             # Все пины: ADC, DAC, Ethernet, LEDs
│   ├── rtl/
│   │   ├── adc_if.v                 # Параллельный ввод 12 бит @ 60 МГц
│   │   ├── dac_if.v                 # Параллельный вывод 14 бит @ 60 МГц
│   │   ├── clk_60mhz.v              # MMCM wrapper: FCLK → 60 МГц + 25 МГц ETH
│   │   └── sdr_top.v                # Toplevel: PS + PL интеграция
│   ├── sim/
│   │   ├── tb_adc_if.v
│   │   └── tb_dac_if.v
│   └── scripts/
│       ├── create_project.tcl       # Создание проекта Vivado (запускается 1 раз)
│       ├── create_bd.tcl            # Block Design: PS7 + AXI DMA + interconnect
│       └── build.tcl                # Синтез + имплементация + bitstream
│
├── firmware/                        # Vitis 2022.2, bare metal
│   ├── src/
│   │   ├── main.c
│   │   ├── platform/
│   │   │   ├── platform_init.c/h    # Zynq PS init, кэш, MMU
│   │   │   ├── ip101g.c/h           # MDIO: init, autoneg, link status
│   │   │   └── axi_dma.c/h          # AXI DMA driver + ISR
│   │   ├── network/
│   │   │   ├── net_init.c/h         # GEM0 + lwIP init
│   │   │   ├── udp_rx.c/h           # SDRAngel Remote Output (приём от SDRAngel)
│   │   │   ├── udp_tx.c/h           # SDRAngel Remote Input (отправка в SDRAngel)
│   │   │   └── http_rest.c/h        # REST API управления (порт 8888)
│   │   ├── protocol/
│   │   │   ├── sdrangel_frame.c/h   # Сборка/разборка superframe
│   │   │   └── cm256.c/h            # FEC Cauchy MDS (порт cm256cc)
│   │   └── tasks/
│   │       ├── rx_task.c/h          # FreeRTOS: ADC → DDR → UDP TX
│   │       └── tx_task.c/h          # FreeRTOS: UDP RX → DDR → DAC
│   ├── lscript.ld                   # Linker script (DDR layout)
│   └── bsp/                         # Vitis BSP (генерируется, в .gitignore)
│
├── docs/
│   ├── architecture.md              # Структурная схема потоков данных
│   ├── pinout.md                    # Полная таблица пинов (из EBAZ4205-ADC-DAC.md)
│   ├── sdrangel_protocol.md         # Описание UDP-протокола Remote Input/Output
│   └── timing.md                    # Временные диаграммы ADC/DAC интерфейсов
│
└── tools/
    ├── test_udp_rx.py               # Имитация SDRAngel Remote Input (PC)
    └── test_udp_tx.py               # Имитация SDRAngel Remote Output (PC)
```

---

## План работ — пошаговые запросы

Формат каждого пункта:
- **Уровень**: О = обычный, ГИ = глубокое исследование, ПР = проектная работа
- **Передать в запросе**: что нужно приложить или указать явно

---

### Фаза 1 — FPGA (Vivado)

---

#### 1.1 XDC файл ограничений
**Уровень**: ПР

Генерирует: `hardware/constraints/ebaz4205.xdc`

Содержит все пины: ADC0–ADC11, OTR, CLK_ADC, DAC0–DAC13, CLK_DAC, PD,
GEM0 MII (TX/RX), FCLK_CLK3→U18, LEDs, UART.

**Передать в запросе**:
- Файл `EBAZ4205-ADC-DAC.md` (уже в пространстве)
- Схему `ebaz4205_schematic_color.pdf` (уже в пространстве)
- Подтверждение: IOSTANDARD = LVCMOS33 для всех IO-банков PL

---

#### 1.2 Tcl-скрипты создания проекта Vivado
**Уровень**: ПР

Генерирует: `hardware/scripts/create_project.tcl`, `build.tcl`

Скрипт создаёт проект Vivado 2022.2, добавляет RTL-источники, XDC,
запускает синтез/имплементацию, генерирует bitstream.
Запускается: `vivado -mode batch -source create_project.tcl`

**Передать в запросе**:
- Результат п. 1.1 (XDC файл)
- Целевое устройство: xc7z010clg400-1

---

#### 1.3 Модуль тактирования MMCM
**Уровень**: ПР

Генерирует: `hardware/rtl/clk_60mhz.v`

MMCM принимает FCLK_CLK0 (100 МГц из PS), выдаёт:
- clk_60mhz — для ADC/DAC интерфейсов и PL логики
- clk_25mhz — выводится на U18 для IP101G (обязательно!)

**Передать в запросе**:
- Реальная частота FCLK_CLK0 (100 МГц — стандарт для EBAZ4205,
  уточнить в PS7 конфигурации Block Design)
- Требование: оба выхода должны быть фазово согласованы

---

#### 1.4 RTL: Интерфейс ADC (AD9226)
**Уровень**: ПР

Генерирует: `hardware/rtl/adc_if.v`, `hardware/sim/tb_adc_if.v`

Параллельный ввод 12 бит по переднему фронту 60 МГц.
Пины: ADC0(N20)..ADC11(U20), OTR(V20), CLK(M19).
Выход: AXI-Stream (TDATA 16 бит знаковый, TVALID, TREADY).
OTR — флаг переполнения, пишется в старший бит или отдельный сигнал.

**Передать в запросе**:
- Файл `ad9226.pdf` (уже в пространстве) — для временны́х диаграмм
- Файл `AD9226-V1.2-board.pdf` (уже в пространстве)
- Файл `EBAZ4205-ADC-DAC.md` (уже в пространстве)

---

#### 1.5 RTL: Интерфейс DAC (DAC904)
**Уровень**: ПР

Генерирует: `hardware/rtl/dac_if.v`, `hardware/sim/tb_dac_if.v`

Параллельный вывод 14 бит по переднему фронту 60 МГц.
Пины: DAC0(H16)..DAC13(G20), CLK(A20), PD(J18).
Вход: AXI-Stream (TDATA 16 бит, младшие 14 используются).
PD управляется через AXI-Lite регистр (power-down режим).

**Передать в запросе**:
- Файл `dac904-14bit.pdf` (уже в пространстве)
- Файл `DAC904-board.pdf` (уже в пространстве)
- Файл `EBAZ4205-ADC-DAC.md` (уже в пространстве)

---

#### 1.6 Block Design (PS7 + AXI DMA)
**Уровень**: ПР

Генерирует: `hardware/scripts/create_bd.tcl`

Tcl-скрипт создаёт Block Design в Vivado:
- PS7: GEM0 MII, FCLK_CLK0 100 МГц, FCLK_CLK3 25 МГц, DDR3, UART0
- AXI DMA (2 канала: S2MM для ADC, MM2S для DAC)
- AXI Interconnect
- MMCM (из п. 1.3)
- Подключение AXI-Stream от adc_if и к dac_if
- Прерывания DMA → PS GIC

**Передать в запросе**:
- Результаты пп. 1.3, 1.4, 1.5 (имена портов модулей)
- Целевое устройство: xc7z010clg400-1

---

#### 1.7 Toplevel и финальная интеграция FPGA
**Уровень**: ПР

Генерирует: `hardware/rtl/sdr_top.v`

Toplevel обёртка: инстанцирует BD wrapper + adc_if + dac_if + clk_60mhz.
Связывает все внешние пины с портами модулей.

**Передать в запросе**:
- Результаты пп. 1.3–1.6 (финальные порты всех модулей)
- XDC файл из п. 1.1

---

### Фаза 2 — Firmware (Vitis, Bare Metal)

---

#### 2.1 Platform init + BSP конфигурация
**Уровень**: ПР

Генерирует: `firmware/src/platform/platform_init.c/h`, `lscript.ld`

Инициализация Zynq PS: кэш L1/L2, MMU (некэшируемые регионы для DMA),
UART для отладки. Linker script с корректным DDR layout
(резервирует некэшируемый регион для DMA-буферов).

**Передать в запросе**:
- Bitstream из Фазы 1 (или `.hdf`/`.xsa` файл экспорта из Vivado)
- Объём DDR на EBAZ4205: уточнить по схеме (обычно 256 МБ)

---

#### 2.2 Драйвер IP101G (MDIO)
**Уровень**: ПР

Генерирует: `firmware/src/platform/ip101g.c/h`

Init последовательность через GEM0 MDIO:
PHY address (из схемы), software reset, autonegotiation 100BASE-TX,
MII mode enable, link status polling.

**Передать в запросе**:
- Файл `IP101GRI.PDF` (уже в пространстве)
- PHY address с платы (из схемы `ebaz4205_schematic_color.pdf`) — обычно 0x01

---

#### 2.3 AXI DMA драйвер + ISR
**Уровень**: ПР

Генерирует: `firmware/src/platform/axi_dma.c/h`

Обёртка над Xilinx xaxidma BSP:
- Инициализация обоих каналов (S2MM/MM2S)
- ISR для FreeRTOS (даёт семафор по завершению Transfer)
- Двойная буферизация (ping-pong): пока один буфер передаётся, другой заполняется
- Функции: `dma_rx_start()`, `dma_tx_start()`, `dma_rx_wait()`, `dma_tx_wait()`

**Передать в запросе**:
- Результат п. 1.6 (адреса AXI DMA из Block Design — из `.xsa`)
- Размер буфера: рассчитать исходя из 60 МГц × 2 байт × N мс задержки

---

#### 2.4 lwIP + GEM0 инициализация
**Уровень**: ПР

Генерирует: `firmware/src/network/net_init.c/h`

Инициализация lwIP в режиме FreeRTOS (не NO_SYS).
GEM0 MAC, статический IP или DHCP (выбирается макросом).
Запуск lwIP tcpip_thread.

**Передать в запросе**:
- Результат п. 2.1 (инициализированная платформа)
- Результат п. 2.2 (инициализированный PHY)
- Желаемый статический IP (например, 192.168.1.100) или DHCP

---

#### 2.5 SDRAngel Remote Protocol: анализ и структуры данных
**Уровень**: ГИ

Генерирует: `firmware/src/protocol/sdrangel_frame.h`, `docs/sdrangel_protocol.md`

Анализ формата UDP-фрейма SDRAngel Remote Input/Output:
- Структура superframe (1 metadata + 127 IQ блоков + FEC блоки)
- Формат metadata (sample rate, центральная частота, timestamp)
- Формат IQ блока (127 × 126 сэмплов по 16 бит)
- C-структуры для сериализации/десериализации

**Передать в запросе**:
- Исходники SDRAngel `remoteinputudphandler.h`, `remoteoutputudphandler.h`,
  `remoteoutputudphandler.cpp` — переименовать в `.txt` и загрузить,
  **ИЛИ** вставить текст блоком кода в чат

---

#### 2.6 Порт cm256cc FEC на bare metal
**Уровень**: ПР

Генерирует: `firmware/src/protocol/cm256.c/h`

Cauchy MDS block erasure codec — чистый C без OS зависимостей.
Адаптация под Zynq: убрать SIMD (или использовать NEON Cortex-A9),
убрать динамическую аллокацию (статические буферы).

**Передать в запросе**:
- Исходники `cm256.h`, `cm256.cpp` из `github.com/f4exb/cm256cc` —
  переименовать в `.txt` и загрузить
- Результат п. 2.5 (размеры блоков FEC)

---

#### 2.7 UDP TX: отправка IQ в SDRAngel (RX-путь)
**Уровень**: ПР

Генерирует: `firmware/src/network/udp_tx.c/h`, `firmware/src/tasks/rx_task.c/h`

FreeRTOS задача: читает DMA-буфер с ADC-данными → конвертирует 12→16 бит знак →
собирает SDRAngel superframe → применяет FEC → отправляет UDP.
Управление потоком: если сеть не успевает, дропает фреймы с логированием.

**Передать в запросе**:
- Результаты пп. 2.3, 2.4, 2.5, 2.6

---

#### 2.8 UDP RX: приём IQ из SDRAngel (TX-путь)
**Уровень**: ПР

Генерирует: `firmware/src/network/udp_rx.c/h`, `firmware/src/tasks/tx_task.c/h`

FreeRTOS задача: принимает UDP фреймы от SDRAngel → декодирует FEC →
извлекает IQ → конвертирует → записывает в DMA-буфер → запускает DMA MM2S к DAC.
Джиттер-буфер: очередь FreeRTOS на N фреймов.

**Передать в запросе**:
- Результаты пп. 2.3, 2.4, 2.5, 2.6

---

#### 2.9 HTTP REST управляющий сервер
**Уровень**: ПР

Генерирует: `firmware/src/network/http_rest.c/h`

Минимальный HTTP/1.0 сервер на lwIP (порт 8888).
Эндпоинты для SDRAngel:
- `GET /sdrangel` — возможности устройства
- `PATCH /sdrangel/deviceset/0/device/settings` — установка параметров
  (центральная частота, sample rate, усиление)
- `GET /sdrangel/deviceset/0/device/run` — статус

**Передать в запросе**:
- Результат п. 2.4 (lwIP инициализация)
- Документацию REST API SDRAngel (из `github.com/f4exb/sdrangel/blob/master/swagger/`)
  — нужны только эндпоинты Remote Input/Output

---

#### 2.10 IQ конвертация и управление буферами
**Уровень**: О

Генерирует: `firmware/src/protocol/iq_convert.c/h`

Функции преобразования:
- ADC: uint12 unsigned → int16 signed (вычесть 2048, сдвиг)
- DAC: int16 signed → uint14 unsigned (добавить 8192, маскирование)
- Нормализация уровня (коэффициент усиления программно)
- Опционально: DC-blocking фильтр первого порядка

**Передать в запросе**: ничего дополнительного

---

### Фаза 3 — Интеграция и отладка

---

#### 3.1 Python тест-скрипты (сторона PC)
**Уровень**: ПР

Генерирует: `tools/test_udp_rx.py`, `tools/test_udp_tx.py`

`test_udp_rx.py`: имитирует SDRAngel Remote Input на PC —
принимает UDP фреймы от EBAZ4205, декодирует, сохраняет IQ в файл.
`test_udp_tx.py`: имитирует SDRAngel Remote Output —
читает IQ файл, собирает фреймы, отправляет на EBAZ4205.
Используется для отладки до подключения реального SDRAngel.

**Передать в запросе**:
- Результат п. 2.5 (формат фреймов)

---

#### 3.2 ILA (Integrated Logic Analyzer) проекция
**Уровень**: О

Генерирует: дополнение к `create_bd.tcl` — добавляет ILA ядра в Block Design.

Точки наблюдения:
- AXI-Stream от ADC (TDATA, TVALID, TREADY)
- AXI-Stream к DAC
- DMA статус

**Передать в запросе**:
- Результат п. 1.6 (Block Design — имена сигналов)

---

#### 3.3 Отладка и финальная интеграция
**Уровень**: ГИ

Диагностика типичных проблем: задержка DMA, потери UDP, несинхронность
ADC/DAC клоков, проблемы autoneg IP101G.
Чеклист запуска по шагам: UART лог → ILA → Wireshark → SDRAngel.

**Передать в запросе**:
- Симптомы конкретной проблемы
- UART лог или сообщения об ошибках Vivado/Vitis

---

## Зависимости между этапами

```
1.1 XDC
 └─→ 1.2 Tcl проект
      └─→ 1.3 MMCM ─┐
      └─→ 1.4 ADC  ─┤─→ 1.6 Block Design ─→ 1.7 Toplevel → .xsa
      └─→ 1.5 DAC  ─┘
                              ↓
                         2.1 Platform (.xsa)
                          ├─→ 2.2 IP101G
                          ├─→ 2.3 DMA
                          └─→ 2.4 lwIP
                               ↓
              2.5 Protocol ←── 2.6 FEC
               ├─→ 2.7 UDP TX + 2.10 IQ
               ├─→ 2.8 UDP RX
               └─→ 2.9 REST
                    ↓
              3.1 Test scripts → 3.2 ILA → 3.3 Debug
```
