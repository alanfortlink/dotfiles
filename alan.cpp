int op(int a, int b){
  return a + b;
}

int parse(int a) {
  return a + 1;
}

int somar(int a, int b){
  a = parse(a);
  b = parse(b);

  return op(a, b);
}

int main(){
  int c = 10;
  int d = 20;

  int e = somar(20, 10);

  return 0;
}
