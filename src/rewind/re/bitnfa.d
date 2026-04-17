module rewind.re.bitnfa;

enum mul = 0x9E3779B97F4A7C15L;
enum sihtLog2 = 6;
enum sihtSize = 1 << sihtLog2;

ulong hash(ulong x) {
    return (x * mul) >> (64 - sihtLog2);
}

// aka simple immutable hash table
// the idea is that it's build once and used many times for lookups
struct SIHT {
    ulong[sihtSize] keys = -1;
    ulong[sihtSize] values = -1;

    void insert(ulong key, ulong value) {
        auto h = hash(key);
        auto idx = h % sihtSize;
        for (;;) {
            assert(keys[idx] != key); // prevent double inserts
            if (keys[idx] == -1) {
                keys[idx] = key;
                values[idx] = value;
                break;
            }
            idx = (idx + 1) % sihtSize;
        }
    }

    ulong opIndex(size_t key) {
        auto h = hash(key);
        auto idx = h % sihtSize;
        for (;;) {
            if (keys[idx] == key) {
                return values[idx];
            }
            if (keys[idx] == -1) {
                return -1;
            }
            idx = (idx + 1) % sihtSize;
        }
    }
}

struct BitNFA {
    ulong[256] table;

}
