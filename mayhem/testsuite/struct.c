struct point {
	int x, y;
};

static int dist2(struct point p)
{
	return p.x * p.x + p.y * p.y;
}

int main(void)
{
	struct point a = {3, 4};
	return dist2(a);
}
