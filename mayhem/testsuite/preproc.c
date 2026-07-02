#define SQR(x) ((x) * (x))
#define N 4

typedef unsigned long ulong;

enum color { RED, GREEN, BLUE };

static ulong fib(ulong n)
{
	return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

int main(void)
{
	int arr[N] = {0};
	enum color c = GREEN;
	arr[c] = SQR(3);
	return (int)fib(arr[c] % N);
}
