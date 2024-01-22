class Calculator {
public:
  int sum(int a, int b) { return a + b; }
  int sub(int a, int b) { return a - b; }
};

int main() {
  Calculator calc;

  int a = 1, b = 2;
  int result = calc.sum(a, b);
  int c = calc.sum(10, 20);

  int k = calc.sub(1, 2);

  int k  = calc.sub(20, 10);

  return 0;
}
