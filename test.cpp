#include <vector>

class Calculator {
public:
  int sum(int a, int b) { return a + b; }
  int sub(int a, int b) { return a - b; }
};

int main() {
  Calculator calc;

  if (true) {
    int a = 1, b = 2;
    int result = calc.sum(a, b);
  }

  int a = 1, b = 2;
  int result = calc.sum(a, b);
  int c = calc.sum(10, 20);

  int k = calc.sub(1, 2);

  return 0;
}
