pub const RETURN: u8 = 0x1;
pub const ICONST_0: u8 = 0x2;
pub const ICONST_1: u8 = 0x3;
pub const ADD: u8 = 0x4;
pub const SUB: u8 = 0x5;
pub const MUL: u8 = 0x6;
pub const DIV: u8 = 0x7;
pub const CLOSURE: u8 = 0x8;
pub const CALL: u8 = 0x9;

pub const LOAD_0: u8 = 0xA;
pub const LOAD_1: u8 = 0xB;
pub const LOAD_2: u8 = 0xC;
pub const LOAD_3: u8 = 0xD;

pub const LOAD_CONST: u8 = 0xE;

pub const STORE_0: u8 = 0xF;
pub const STORE_1: u8 = 0x10;
pub const STORE_2: u8 = 0x11;
pub const STORE_3: u8 = 0x12;

pub const LOAD_N: u8 = 0x13;
pub const STORE_N: u8 = 0x14;

pub const TO_STRING: []const []const u8 = &.{
    "(0x00) undefined",
    "(0x01) RETURN",
    "(0x02) ICONST_0",
    "(0x03) ICONST_1",
    "(0x04) ADD",
    "(0x05) SUB",
    "(0x06) MUL",
    "(0x07) DIV",
    "(0x08) CLOSURE",
    "(0x09) CALL",
    "(0x0A) LOAD_0",
    "(0x0B) LOAD_1",
    "(0x0C) LOAD_2",
    "(0x0D) LOAD_3",
    "(0x0E) LOAD_CONST",
    "(0x0F) STORE_0",
    "(0x10) STORE_1",
    "(0x11) STORE_2",
    "(0x12) STORE_3",
    "(0x13) LOAD_N",
    "(0x14) STORE_N",
};
