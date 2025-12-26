import math
import matplotlib.pyplot as plt
import numpy as np

def P_k(k, n, T_arrive, E, c):
    def product_term(i):
        prod = 1.0
        for j in range(1, i + 1):
            prod *= (E + j * c)
        return prod

    numerator = product_term(k) / (T_arrive ** k * math.factorial(n - k))

    denominator = 0.0
    for i in range(0, n + 1):
        denominator += product_term(i) / (T_arrive ** i * math.factorial(n - i))

    return numerator / denominator


def C(n, T_arrive, E, c):
    """
    C = sum_{i=0}^n i * P_i
    """
    total = 0.0
    for i in range(0, n + 1):
        total += i * P_k(i, n, T_arrive, E, c)
    return total


# 定义常数
T_arrive = 1.0  # 事件到达的时间间隔

# 定义不同的 E 和 c 值
E_values = [0.02]
c_values = [0.03]

# 计算 y = (n - C(n, T_arrive, E, c)) / n
n_values = np.arange(1, 101)  # 从 1 到 100 的整数

# 绘制图形
plt.figure(figsize=(10, 6))
for E in E_values:
    for c in c_values:
        y_values = [(n - C(n, T_arrive, E, c)) / n for n in n_values]
        plt.plot(n_values, y_values, label=f'E={E}, c={c}')

plt.title('y = (n - C(n, T_arrive, E, c)) / n')
plt.xlabel('n')
plt.ylabel('y')
plt.legend()
plt.grid(True)
plt.show()

