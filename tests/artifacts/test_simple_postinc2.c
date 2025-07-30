void test_copy(char *dst, char *src, int n) {
    while (n--) {
        *dst++ = *src++;
    }
}