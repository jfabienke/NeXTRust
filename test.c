// Simple test program to see which M68k instructions are actually generated
int add_test(int a, int b) {
    return a + b;
}

int multiply_test(int a, int b) {
    return a * b;
}

void branch_test(int condition) {
    if (condition) {
        // do something
    }
}

int main() {
    int result = add_test(5, 10);
    result = multiply_test(result, 2);
    branch_test(result > 20);
    return result;
}
