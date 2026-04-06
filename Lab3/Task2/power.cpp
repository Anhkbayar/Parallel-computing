#include <iostream>

int nextPowerOf2(int n)
{
    n--;
    n |= n >> 1;
    n |= n >> 2;
    n |= n >> 4;
    n |= n >> 8;
    n |= n >> 16;
    n++;
    return n;
}

int main()
{
    int arr[] = {3, 2, 5, 26, 23, 11, 7, 9};
    for (int n : arr)
        std::cout << n << " ";

    std::cout << "\n\n";

    for (int &n : arr)
        n = nextPowerOf2(n);

    for (int n : arr)
        std::cout << n << " ";
}