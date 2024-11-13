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
  return 0;
}
