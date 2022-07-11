from litex.build.generic_platform import *
from litex.build.altera import AlteraPlatform
from litex.build.altera.programmer import USBBlaster

from migen import *
from migen.genlib.resetsync import AsyncResetSynchronizer

from litex.build.io import DDROutput

from litex.soc.cores.clock import CycloneIVPLL
from litex.soc.integration.soc_core import *
from litex.soc.integration.builder import *

from litedram.modules import IS42S16320
from litedram.phy import GENSDRPHY

from litex.soc.cores.gpio import GPIOOut, GPIOIn

# IOs ----------------------------------------------------------------------------------------------

_io = [
    # Clk
    ("clk50", 0, Pins("Y2"), IOStandard("3.3-V LVTTL")),

    # Serial
    ("serial", 0,
        Subsignal("tx", Pins("G9"), IOStandard("3.3-V LVTTL")), # Use built-in Tx RS32 port
        Subsignal("rx", Pins("G12"), IOStandard("3.3-V LVTTL"))  #  Use built-in Rx RS32 port
    ),

    # Leds
    ("user_led", 0, Pins("E21"), IOStandard("3.3-V LVTTL")),
    ("user_led", 1, Pins("E22"), IOStandard("3.3-V LVTTL")),
    ("user_led", 2, Pins("E25"), IOStandard("3.3-V LVTTL")),
    ("user_led", 3, Pins("E24"), IOStandard("3.3-V LVTTL")),
    ("user_led", 4, Pins("H21"), IOStandard("3.3-V LVTTL")),
    ("user_led", 5, Pins("G20"), IOStandard("3.3-V LVTTL")),
    ("user_led", 6, Pins("G22"), IOStandard("3.3-V LVTTL")),
    ("user_led", 7, Pins("G21"), IOStandard("3.3-V LVTTL")),
    ("user_led", 8, Pins("F17"), IOStandard("3.3-V LVTTL")),
    ("user_led", 9, Pins("G19"), IOStandard("3.3-V LVTTL")),
    ("user_led", 10, Pins("F19"), IOStandard("3.3-V LVTTL")),
    ("user_led", 11, Pins("E19"), IOStandard("3.3-V LVTTL")),
    ("user_led", 12, Pins("F21"), IOStandard("3.3-V LVTTL")),
    ("user_led", 13, Pins("F18"), IOStandard("3.3-V LVTTL")),
    ("user_led", 14, Pins("E18"), IOStandard("3.3-V LVTTL")),
    ("user_led", 15, Pins("J19"), IOStandard("3.3-V LVTTL")),
    ("user_led", 16, Pins("H19"), IOStandard("3.3-V LVTTL")),
    ("user_led", 17, Pins("J17"), IOStandard("3.3-V LVTTL")),
    ("user_led", 18, Pins("G17"), IOStandard("3.3-V LVTTL")),
    ("user_led", 19, Pins("J15"), IOStandard("3.3-V LVTTL")),
    ("user_led", 20, Pins("H16"), IOStandard("3.3-V LVTTL")),
    ("user_led", 21, Pins("J16"), IOStandard("3.3-V LVTTL")),
    ("user_led", 22, Pins("H17"), IOStandard("3.3-V LVTTL")),
    ("user_led", 23, Pins("F15"), IOStandard("3.3-V LVTTL")),
    ("user_led", 24, Pins("G15"), IOStandard("3.3-V LVTTL")),
    ("user_led", 25, Pins("G16"), IOStandard("3.3-V LVTTL")),
    ("user_led", 26, Pins("H15"), IOStandard("3.3-V LVTTL")),

    # Seven seg
    ("seven_seg", 0, Pins("G18 F22 E17 L26 L25 J22 H22"), IOStandard("3.3-V LVTTL")),
    ("seven_seg", 1, Pins("M24 Y22 W21 W22 W25 U23 U24"), IOStandard("3.3-V LVTTL")),
    ("seven_seg", 2, Pins("AA25 AA26 Y25 W26 Y26 W27 W28"), IOStandard("3.3-V LVTTL")),
    ("seven_seg", 3, Pins("V21 U21 AB20 AA21 AD24 AF23 Y19"), IOStandard("3.3-V LVTTL")),
    ("seven_seg", 4, Pins("AB19 AA19 AG21 AH21 AE19 AF19 AE18"), IOStandard("3.3-V LVTTL")),
    ("seven_seg", 5, Pins("AD18 AC18 AB18 AH19 AG19 AF18 AH18"), IOStandard("3.3-V LVTTL")),
    ("seven_seg", 6, Pins("AA17 AB16 AA16 AB17 AB15 AA15 AC17"), IOStandard("3.3-V LVTTL")),
    ("seven_seg", 7, Pins("AD17 AE17 AG17 AH17 AF17 AG18 AA14"), IOStandard("3.3-V LVTTL")),

    # Keys
    ("push_btn", 0, Pins("M23"), IOStandard("3.3-V LVTTL")),
    ("push_btn", 1, Pins("M21"), IOStandard("3.3-V LVTTL")),
    ("push_btn", 2, Pins("N21"), IOStandard("3.3-V LVTTL")),
    ("push_btn", 3, Pins("R24"), IOStandard("3.3-V LVTTL")),

    # Switches
    ("user_swt", 0, Pins("AB28"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 1, Pins("AC28"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 2, Pins("AC27"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 3, Pins("AD27"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 4, Pins("AB27"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 5, Pins("AC26"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 6, Pins("AD26"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 7, Pins("AB26"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 8, Pins("AC25"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 9, Pins("AB25"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 10, Pins("AC24"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 11, Pins("AB24"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 12, Pins("AB23"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 13, Pins("AA24"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 14, Pins("AA23"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 15, Pins("AA22"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 16, Pins("Y24"), IOStandard("3.3-V LVTTL")),
    ("user_swt", 17, Pins("Y23"), IOStandard("3.3-V LVTTL")),

    # SDR SDRAM
    ("sdram_clock", 0, Pins("AE5"), IOStandard("3.3-V LVTTL")),
    ("sdram", 0,
        Subsignal("a",     Pins(
            "R6 V8 U8 P1 V5 W8 W7 AA7",
            "Y5 Y6 R5 AA5 Y7")),
        Subsignal("ba",    Pins("U7 R4")),
        Subsignal("cs_n",  Pins("T4")),
        Subsignal("cke",   Pins("AA6")),
        Subsignal("ras_n", Pins("U6")),
        Subsignal("cas_n", Pins("V7")),
        Subsignal("we_n",  Pins("V6")),
        Subsignal("dq", Pins(
            "W3 W2  V4  W1  V3  V2  V1  U3",
            "Y3 Y4 AB1 AA3 AB2 AC1 AB3 AC2")),
        Subsignal("dm", Pins("U2 W4")),
        IOStandard("3.3-V LVTTL")
    ),
]

# Platform -----------------------------------------------------------------------------------------

class Platform(AlteraPlatform):
    default_clk_name   = "clk50"
    default_clk_period = 1e9/50e6

    def __init__(self, toolchain="quartus"):
        AlteraPlatform.__init__(self, "EP4CE115F29C7", _io, toolchain=toolchain)

    def create_programmer(self):
        return USBBlaster()

    def do_finalize(self, fragment):
        AlteraPlatform.do_finalize(self, fragment)
        self.add_period_constraint(self.lookup_request("clk50", loose=True), 1e9/50e6)

# CRG ----------------------------------------------------------------------------------------------

class _CRG(Module):
    def __init__(self, platform, sys_clk_freq):
        self.rst = Signal()
        self.clock_domains.cd_sys    = ClockDomain()
        self.clock_domains.cd_sys_ps = ClockDomain()

        # # #

        # Clk / Rst
        clk50 = platform.request("clk50")

        # PLL
        self.submodules.pll = pll = CycloneIVPLL(speedgrade="-7")
        self.comb += pll.reset.eq(self.rst)
        pll.register_clkin(clk50, 50e6)
        pll.create_clkout(self.cd_sys,    sys_clk_freq)
        pll.create_clkout(self.cd_sys_ps, sys_clk_freq, phase=90)

        # SDRAM clock
        self.specials += DDROutput(1, 0, platform.request("sdram_clock"), ClockSignal("sys_ps"))

# BaseSoC ------------------------------------------------------------------------------------------

class BaseSoC(SoCCore):
    def __init__(self, sys_clk_freq=int(50e6), **kwargs):
        platform = Platform()

        # CRG --------------------------------------------------------------------------------------
        self.submodules.crg = _CRG(platform, sys_clk_freq)

        # SoCCore ----------------------------------------------------------------------------------
        SoCCore.__init__(self, platform, sys_clk_freq, ident="LiteX SoC on DE2-115", **kwargs)

        # SDR SDRAM --------------------------------------------------------------------------------
        if not self.integrated_main_ram_size:
            self.submodules.sdrphy = GENSDRPHY(platform.request("sdram"), sys_clk_freq)
            self.add_sdram("sdram",
                phy           = self.sdrphy,
                module        = IS42S16320(self.clk_freq, "1:1"),
                l2_cache_size = kwargs.get("l2_size", 8192)
            )

        # LEDS -------------------------------------------------------------------------------------
        self.submodules.user_leds = GPIOOut(self.platform.request_all("user_led"))

        # Seven seg --------------------------------------------------------------------------------
        self.submodules.seven_seg = GPIOOut(self.platform.request_all("seven_seg"))

        # Push buttons -----------------------------------------------------------------------------
        self.submodules.push_btn = GPIOIn(Cat(self.platform.request_all("push_btn")), with_irq=True)
        self.push_btn.ev.finalize()
        self.add_interrupt("push_btn")

        # Switches ---------------------------------------------------------------------------------
        self.submodules.user_swt = GPIOIn(Cat(self.platform.request_all("user_swt")), with_irq=True)
        self.user_swt.ev.finalize()
        self.add_interrupt("user_swt")


# Build --------------------------------------------------------------------------------------------

def main():
    from litex.soc.integration.soc import LiteXSoCArgumentParser
    parser = LiteXSoCArgumentParser(description="LiteX SoC on DE2-115")
    target_group = parser.add_argument_group(title="Target options")
    target_group.add_argument("--build",        action="store_true", help="Build design.")
    target_group.add_argument("--load",         action="store_true", help="Load bitstream.")
    target_group.add_argument("--sys-clk-freq", default=50e6,        help="System clock frequency.")
    builder_args(parser)
    soc_core_args(parser)
    args = parser.parse_args()

    soc = BaseSoC(
        sys_clk_freq = int(float(args.sys_clk_freq)),
        **soc_core_argdict(args)
    )
    builder = Builder(soc, **builder_argdict(args))
    if args.build:
        builder.build()

    if args.load:
        prog = soc.platform.create_programmer()
        prog.load_bitstream(builder.get_bitstream_filename(mode="sram"))

if __name__ == "__main__":
    main()
