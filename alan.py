def op(a, b):
    return a + b


def parse(a):
    return a + 1


def somar(a, b):
    a = parse(a)
    b = parse(b)

    return op(a, b)


def __main__():
    print(somar(1, 2))
