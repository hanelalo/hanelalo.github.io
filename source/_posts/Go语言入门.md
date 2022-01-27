---
title: Go语言入门
date: 2022-01-03 19:56:16
tags: Go
categories: Go
cover: https://hanelalo.github.io/images/202201032000947.png
---

# Go 语言入门

> 我是一个 Java 开发者，所以本文大多是与 Java 的语法对比，方便作为一个 Java 开发者的自己理解，所以有些和 Java 类似的语法，只会写一个例子，不会再做解释。
>
> 本文是学习 Go 官方的教程 [A Tour of Go](https://go.dev/tour/welcome/1) 时按自己的理解写下。

和 Java 类似，Go 程序也是从一个 main 函数开始。

```go
package main

import (
    "fmt"
    "math"
)

func main() {
    fmt.Println(math.pi)
}
```

* package 关键字就是包的意思，后面接包名即可
* import 关键字用来引入其他的第三库
* func 关键字用来定义一个函数。

## 函数（方法）

### 函数定义

```go
func add(x int,y int) int{
    return x + y
}
```

定义一个方法的形式是`func <methodName>[arg1 typeOfArg1, arg2 typeOfArg2] <returnType> {[function body]}`。

如果参数类型一样，也可以简写成如下形式：

```go
func add(x, y int) int{
    return x + y
}
```

即：`func <methodName>[arg1, arg2 typeOfArg] <returnType> {[function body]}`

### 多返回值函数定义

Go 还支持一个函数有多个返回值：

```go
func swap(x, y string) (string, string) {
    return y, x
}
```

如上，多个返回值时，用括号讲返回值得类型括起来，用逗号分割即可。

### 已命名返回值

```go
func split(sum int) (x,y int) {
    x = sum * 4 / 9
    y = sum - x
    return
}
```

如上，return 关键字后面没有跟任何代码，函数的返回值类型不再是单纯定义类型，而是两个变量，在 `split` 方法体中改变了 x、y 两个变量的值，调用 split 方法后的最终返回值，就是函数体执行完后 x、y 最终的值。

### 函数的调用

```go
func main(){
    fmt.Println(add(42, 13))
}
```

直接使用方法名拼接参数的形式即可。

## 变量

```go
package main

import "fmt"

var c, python, java bool

func main() {
    var i int
    fmt.Println(i, c, python, java)
}
```

通过 `var` 关键字定义变量的 形式` var <var_name1>[,var_name2...] type1`。

变量可以定义在函数内，也可以定义在函数外，上面这种定义方式，变量的值都是类型对应的初始值。还可以在定义变量时就给一个初始化的值。

```go
package main

import "fmt"

var i, j int = 1, 2

func main(){
    var c, python, java = true, false, "no!"
    fmt.Println(i, j, c, python, java)
}
```

相对于前面的定义方式，这里不再指定类型，而是直接使用 `=` 符号对每个变量赋值，而变量类型，由初始化的值得类型决定，且可以使用同一个 var 关键字初始化多个不同类型的变量。

上面这种赋予值得变量初始化，还有两一种更简单的写法：

```go
package main

import "fmt"

func main() {
    var i, j int = 1, 2
    k, m := 3, 4
    c, python, java := true, false, "no!"

    fmt.Println(i, j, k, m, c, python, java)
}
```

简单来讲就是变量名和值之间使用 `:=` 连接，指定类型的同时也进行了赋值，且同样可以同时定义多个变量。

## 基础数据类型

* bool

  布尔类型，其实就是 true 和 false 这两种值。

* string

  字符串类型。

* int、int8、int16、int32、int64

  整数类型，区分正负号，后面的数字代码类型的大小，int 在后面有单独说明。

  比如 int8 表示一个 int8 类型的变量占用 8 bit，因为最高位用来作为正负数表示，1 表示负数，0 表示非负数，所以非负数最高位位 0，实际值只有七位，所以最大只有 二进制数`01111111`，也就是 `2^8-1 = 127`，负数最高位为 1，此时如果所有位都是 1，二进制数为 `11111111`，负数的实际值有 8 位，不过最高位一直是 1，所以最小的负数为 `-2^8 = -128`。

  > 这里会发现一个有趣的等式：2 ^n-1 = 2^0+2^1+2^2+...+2^(n-1)

* uint、uint8、uint16、uint32、uint64、uintptr

  无符号整数类型，只表示非负整数，后面的数字依然表示类型的大小。

  比如 uint8, 表示一个 uint8 类型的变量有 8 bit，最小为 0，最大为 `2^8-1 = 255`。 

* byte

  可理解为别名为 byte 的 uint8。

* rune

  和 int32 一样。官方教程讲这个类型用来表示 Unicode。

* float32、float64

  浮点型，后面的数字依然是所占的 bit 数。

* complex64、complex128

  高等数学里面的`复数`。

  ```go
  package main
  
  import "fmt"
  
  func main(){
      c := complex(2, 3)
      fmt.Println(x) // 输出结果: (2+3i)
      c := 3+4i
      fmt.Println(x) // 输出结果: (3+4i)
      realPart := real(c) // 实数部分
      imagPart := imag(c) // 虚数部分
      fmt.Println(realPart, imagPart) // 输出结果: 3 4
  }
  ```

int、uint、uintptr 在 32 位操作系统上是 32 bit，在 64 位操作系统上是 64 bit，一般都是建议使用 int，除非有什么特殊的变量大小要求或者需要无符号 int。数字类型的初始值是 0，bool 类型初始值为 false，string 类型初始值为 `""`。

Go 中各个类型的转换需要显示转换，比如 int8 转 int16：

```go
package main

import (
    "fmt"
)

func main() {
    var x int8 = 3
    var y int16 = int16(x)
    fmt.Println(y)
}
```

## 常量

常量和变量的定义类似，只不过不能使用 `:=` 赋值，而是直接使用 `=`。

## 分支、循环

### for

按照 Java 的 for 循环语法，分为初始条件、循环条件、循环后操作、循环体，即 `for(初始条件;循环条件;循环后操作){循环体}`。

Go 也是一样，不过没有使用小括号将初始条件、循环条件、循环后操作括起来，所以 Go 的 for 循环如下:

```go
sum := 0
for i := 0; i < 10; i++ {
    sum += i
}
j := 0
for ; j < 10; j++ {
    sum += j
}
```

在 for 后面定义的循环变量 i，作用域只在这个 for 循环。和 Java 一样，Go 的 for 循环的初始条件部分也可以不写，但是后面的分号是必要的。

### while

Go 中的 while 和 Java 不一样，而是使用了 for 关键字。

```go
sum := 1
for sum < 1000 {
    sum += sum
}
fmt.Println(sum)
```

### 死循环

```go
for {}
```

### if

和 Java 的区别在于，Go 中 if 的条件语句没有用小括号括起来，而大括号是必须要的。

```go
func sqrt(x float64) string {
    if x < 0 {
        return sqrt(-x) + "i"
    }
    return fmt.Sprint(math.Sqrt(x))
}
```

Java 中的 if 语句的小括号内还可以有简单的逻辑语句，Go 也可以。

```go
func pow(x, n, lim float64) string {
    if v := math.Pow(x, n); v < lim {
        return v
    }
    return lim
}
```

### if...else...

```go
func pow(x, n, lim float64) string {
    if v := math.Pow(x, n); v < lim {
        return v
    }else {
        return lim
    }
}
```

`if...else if...` 以及 `if...else if...else...`语法也和 Java 类似，不解释。

### switch

```go
package main

import (
    "fmt"
    "runtime"
)

func main() {
    fmt.Print("Go runs on ")
    os := runtime.GOOS;
    switch os {
    case "darwin":
        fmt.Println("OS X.")
    case "linux":
        fmt.Println("Linux.")
    default:
        fmt.Printf("%s.\n", os)
    }
}
```

和 Java 最大的区别在于，Java 里面每一个 case 执行体最后都需要一个 break 来结束执行，Go 里面已经隐式的加上了 break，所以 Java 里面多个 case 使用同一段 case 执行体的写法在 Go 里面不会达到预期效果。

如果 switch 的条件是空的，就相当于是一个 if 结构体：

```go
package main

import (
    "fmt"
    "time"
)

func main() {
    t := time.Now()
    switch {
    case t.Hour() < 12:
        fmt.Println("Good morning!")
    case t.Hour() < 17:
        fmt.Println("Good afternoon.")
    default:
        fmt.Println("Good evening.")
    }
}
```

比如上面这个，就相当于：

```go
package main

import (
    "fmt"
    "time"
)

func main() {
    t := time.Now()
    if t.Hour() < 12{
        fmt.Println("Good morning!")
    } else if t.Hour() < 17{
        fmt.Println("Good afternoon.")
    } else {
        fmt.Println("Good evening.")
    }
}
```

## Defer

defer 是 Go 里面的一个语法关键字，defer 语句会在函数返回前执行。

```go
package main

import "fmt"

func main(){
    defer fmt.Println("world")

    fmt.Println("hello")
}
```

比如上面这个函数最终会输出的结果是：

```
hello
world
```

因为输出了 hello 之后，函数就要返回了，此时会执行 defer 中的逻辑，输出 world。

但是，这里有一个值得注意的地方，先看下面的代码：

```go
package main

import "fmt"

func main() {
    defer world(getStr())

    fmt.Println("hello")
}

func world(s string) {
    fmt.Println(s)
}

func getStr() string {
    fmt.Println("get world")
    return "world"
}
```

按理说，这里的输出结果应该是：

```
hello
get world
world
```

但是实际的输出结果却是：

```
get world
hello
world
```

这是因为 **defer 语句会先执行内层的函数，只有最外层的函数才会在返回前执行。**

如果有多个 defer 语句，那么这些 defer 语句在函数返回时的执行顺序，就像是一个栈（Stack）一样，最先定义的 defer，最后才执行。

## 指针

> 指针这个东西，第一次见是在 C 语言中，我的理解是，指针记录的是变量的内存地址。

首先需要先认识 `&` 和 `*` 这两个特殊符号。

```go
i := 42
p := &i
j := *p
```

`&` 后接变量名表示获取变量的指针，比如上面的 p 就是变量 i 的指针，`*` 后面接指针变量，就是通过指针获取变量的实际值。

```go
package main

import "fmt"

func main(){
    i := 42
    p := &i
    j := *p
    fmt.Println(i) // 42
    fmt.Println(p) // 0xc00000a098, 这个 16 进制数就是内存地址了
    fmt.Println(j) // 42
    *p = 21 // 通过指针为变量赋值
    fmt.Println(i) // 21
    fmt.Println(j) //42
}
```

输出结果:

```
42
0xc00000a098
42
21
42
```

上面的代码，我们可以知道如下几点：

* 指针的值是指针所表示的变量的虚拟内存地址（额，这是按操作系统层面的说法，其实就是平常说的内存地址），将指针输出就能证明这一点。
* 因为修改了 `*p` 的值之后，j 依然是 42，这说明 `j := *p` 这行代码其实是值传递，其实 j 重新申请了内存，不过内存里的值和 *p 一样而已。

## struct

在 C 语言里面就出现了这个关键字。它其实用来定义多个字段的集合，好吧其实可以理解为 Java 里面的一个类。

### 定义 struct

定义一个 struct 也很简单。

```go
package main

import "fmt"

type Vertex struct {
    X int
    Y int
}

func main(){
    v := Vertex{1,2}
    fmt.Println(v)
    fmt.Println(v.X)
}
```

还记得在 Java 中，对象是要 `new` 出来的，Go 也类似，但是并没有为此专门加一个关键字，而是向上面的代码那样 struct 的名称后面接大括号，括号内写入每个字段的值即可，而要访问内部的字段，直接通过 `变量名.字段名` 的方式就可以访问。

### struct 指针

```go
package main

import "fmt"

type Vertex struct {
    X int
    Y int
}

func main(){
    v := Vertex{1, 2}
    fmt.Println(v) // {1, 2}
    p := &v
    fmt.Println(p) // &{1 2}
    p.X = 1e9
    fmt.Println(v) // {1000000000, 2}
}
```

可以发现这里使用 `p.X` 进行赋值时，按照之前的理解，应该会出错的，因为 p 只是一个内存地址，哪里去找 X 这个字段，但其实 Go 在这里隐式转换成了 `(*p).X`。

初始化一个 struct 实例的时候，如果大括号里面啥也不写，那么每个字段的值将是初始值，如果只想给某些字段赋值，在大括号内就可以使用类似 json 的语法进行赋值。

```go
package main

import "fmt"

type Vertex struct {
    X int
    Y int
}

func main(){
    v1 := Vertex{1, 2}
    fmt.Println(v1) // {1, 2}
    v2 := Vertex{}
    fmt.Println(v2) // {0, 0}
    v3 := Vertex{Y:1}
    fmt.Println(v3) // {0, 3}
}
```

## array

```go
var a [10]int
```

上面的代码便是定义了一个容量大小为 10 的 int 类型的数组变量 a。和 Java 中类似，这样的数组的容量是不可变的。

还可以在定义数组时就将每个元素的值填充进去。

```go
primes := [6]int{2, 3, 5, 7, 11, 13}
```

### Slices

> 翻译为：切片，这里我认为其实是数组切分的意思。

#### 创建 Slices

* 通过数组创建

Slices 其实就是截取数组中的部分元素。

```go
package main

import "fmt"

func main() {
    primes := [6]int{2, 3, 5, 7, 11, 13}

    var s []int = primes[1:4]
    fmt.Println(s)
}
```

比如上面的 `primes[1:4]` 是获取 primes 数组中的下标为 1 一直到下标为 3 的元素，也就是说 `[1,4]` 转换成数学里面的区间概念的话，就是一个前闭后开区间，并且和 Java 一样，数组中元素的下边是从 1 开始。

并且，冒号前后的数字是可以省略的，省略冒号前面的数字表示从下标 0 开始取，省略冒号后面的数字表示一直取到最后一个元素，如果两个数字都省略了，将会获取所有元素。

```go
var s []int = primes[:4] // 从 0 取到 3
var s []int = primes[1:] // 从 1 取到最后
var s []int = primes[:] // 取 primes 中所有元素
```

* 通过 Slices literal syntax（切片文本语法）创建

除了通过 Array 创建，还可以通过下面的方式创建：

```go
s := []int{2, 3, 5, 7, 11, 13}
```

会发现，这跟定义 array 的语法十分相似，只不过 array 指定了数组长度。

* 通过其他的 slices 创建

```go
package main

import "fmt"

func main() {
    var odds =  [8]int{1, 3, 5, 7, 9, 11, 13, 15}
    slice1 := odds[2:]
    fmt.Println(slice1)     // prints [5 7 9 11 13 15]
    slice2 := slice1[2:4]
    fmt.Println(slice2)     // prints [9 11]
}
```

* 通过 make 方法创建

```go
package main

import "fmt"

func main() {
    s := make([]int, 5) // make an int slice of length 5
    fmt.Println(s) // [0 0 0 0 0]
}
```

上面的 make() 函数创建了一个长度和容量都是 5 的 slices。

make() 函数还支持创建长度和容量不一样的 slices。

```go
package main

import "fmt"

func main() {
    printSlice(make([]int, 5))
    printSlice(make([]int, 4, 5))
}

func printSlice(s []int) {
    fmt.Printf("len=%d cap=%d %v\n", len(s), cap(s), s)
}
```

```
len=5 cap=5 [0 0 0 0 0]
len=4 cap=5 [0 0 0 0]
```

#### Slices 和 Array 的区别

> Arrays, after declared of some size, cannot be resized, whereas slices can be resized. Slices are reference-types while arrays are value-type.

数组的容量固定，不能改变容量，但是 Slices 的容量可以改变，Slices 是引用类型，array 是值类型。

#### 引用

Slices 操作并非是重新申请内存才存截取出的数据，里面每一个元素都是原始数组中的数据，通过以下代码就可以证明这一点。

```go
package main

import "fmt"

func main() {
    names := [4]string{
        "John",
        "Paul",
        "George",
        "Ringo",
    }
    fmt.Println(names)

    a := names[0:2]
    b := names[1:3]
    fmt.Println(a, b)

    b[0] = "XXX"
    fmt.Println(a, b)
    fmt.Println(names)
}
```

输出结果：

```
[John Paul George Ringo]
[John Paul] [Paul George]
[John XXX] [XXX George]
[John XXX George Ringo]
```

可以看见，通过数组变量 b 将 b 中的下标为 0 的元素设置为 XXX，而这个元素其实是 names 中的下标为 1 的元素，所以此时再输出 names 的内容，发现 names 下标为 1 的元素的值也变成了 XXX。

#### 长度和容量

```go
package main

import "fmt"

func main() {
    s := []int{2, 3, 5, 7, 11, 13}
    printSlice(s)

    // Slice the slice to give it zero length.
    s = s[:0]
    printSlice(s)

    // Extend its length.
    s = s[:4]
    printSlice(s)

    // Drop its first two values.
    s = s[2:]
    printSlice(s)
}

func printSlice(s []int) {
    fmt.Printf("len=%d cap=%d %v\n", len(s), cap(s), s)
}
```

* 长度是指 slices 结果中包含的元素个数，通过 len() 函数计算。

* 容量是基于做 slices 操作的数组的容量计算的，并且从 slices 结果中的第一个元素开始算，一直到底层数组的最后一个元素，通过 cap() 函数计算。

* 如果 Slice 有足够的容量，可以通过 re-slices 扩展 slices 的长度，但是超出容量会报错。

#### Nil Slice

如果只是定义了一个 slices 变量，而没有为其中的元素赋值，slices 为 nil。

```go
package main

import "fmt"

func main() {
    var s []int
    fmt.Println(s, len(s), cap(s))
    if s == nil {
        fmt.Println("nil!")
    }
}
```

```
[] 0 0
nil!
```

#### Append

```go
package main

import "fmt"

func main() {
    slices := make([]int, 5)
    printSlice(slices)
    s := append(slices, 1)
    s[0] = 1
    printSlice(s)
    printSlice(slices)
}

func printSlice(s []int) {
    fmt.Printf("len=%d cap=%d %v\n", len(s), cap(s), s)
}
```

```
len=5 cap=5 [0 0 0 0 0]
len=6 cap=10 [1 0 0 0 0 1]
len=5 cap=5 [0 0 0 0 0] 
```

从上面代码的运行结果可以知道，append() 函数不仅进行了扩容，而且会新返回一个 slices，而不是修改原有的 slices。

> 整个 slices 相关的知识其实还有一些，可以阅读一下下面的官方博客：
>
> [Slices in GoLang](https://golangdocs.com/slices-in-golang)
>
> [Go Slices: usage and internals](https://go.dev/blog/slices-intro)
>
> [function: append](https://pkg.go.dev/builtin#append)

## Range

> 有点像Java 中的 foreach 语法的味道。

```go
package main

import "fmt"

var pow = []int{1, 2, 4, 8, 16, 32, 64, 128}

func main() {
    for i, v := range pow {
        fmt.Printf("2**%d = %d\n", i, v)
    }
}
```

i 是循环数组下标，v 是下标对应的值，这个顺序是不会变的。

如果只想要下标或者只想要每个下标对应的值，可以像下面这样用下划线代替。

```go
package main

import "fmt"

func main() {
    pow := make([]int, 10)
    for i := range pow {
        pow[i] = 1 << uint(i) // == 2**i
    }
    for _, value := range pow {
        fmt.Printf("%d\n", value)
    }
}
```

因为 range 语法中下标和值得顺序不会变，下标变量在前，值变量在后，所以如果只需要下标的话，不需要用下划线 `_` 代替值变量，但如果只想要值变量，因为前面的下标变量不可少，所以需要用 `_` 代替。

> 下划线 `_` 在这里真的就只是一个占位符而已，并不具有定义一个变量的语义，所以循环里面要是把 `_` 当成下标变量使用是会报错的。

## Maps

可理解为 Java 中的 Map 一样的键值对的数据结构，和 slices 一样，map 的初始化值为 `nil`。

```go
package main

import "fmt"

type Vertex struct {
    Lat, Long float64
}

var m map[string]Vertex

func main() {
    m = make(map[string]Vertex)
    m["Bell Labs"] = Vertex{
        40.68433, -74.39967,
    }
    fmt.Println(m["Bell Labs"])
}
```

定义一个 map 有三种语法：

* 第一种语法：`var m map[string]Vertex` 

  string 就是键的类型，Vertex 是值得类型。

  这种方式因为没有初始化值，所以是 nil，也不能再增加键值对，因为对 nil 执行任何方法都会报错，就像 Java 中常常因为 null 导致空指针一样。

* 第二种语法：`make(map[string]Vertex)`

  通过 make() 函数创建 map。

* 第三种语法

  ```go
  var m = map[string]Vertex{
      "Bell Labs": Vertex{
          40.68433, -74.39967,
      },
      "Google": Vertex{
          37.42202, -122.08408,
      },
  }
  // 省略值的类型名称
  m = map[string]Vertex{
      "Bell Labs": {40.68433, -74.39967},
      "Google":    {37.42202, -122.08408},
  }
  ```

#### 增加键值对

```go
m[key] = value
```

#### 根据键获取值

```go
ele = m[key]
```

#### 删除键值对

```go
delete(m, key)
```

#### 判断 map 中是否存在某个 key

```go
v,ok := m[key]
```

v 是 key 对应的 value，如果不存在，v 就是 value 对应类型的零值；ok 是判断结果，true 表示存在，false 表示不存在。

## 函数变量

函数本身也可以定义成一个变量，并当作函数调用的参数做值传递。

```go
package main

import (
    "fmt"
    "math"
)

func compute(fn func(float64, float64) float64) float64 {
    return fn(3, 4)
}

func main() {
    hypot := func(x, y float64) float64 {
        return math.Sqrt(x*x + y*y)
    }
    fmt.Println(hypot(5, 12))

    fmt.Println(compute(hypot))
    fmt.Println(compute(math.Pow))
}
```

首先定义了一个 compute 函数，参数也是一个入参为两个 float64 类型变量、返回值类型为 float64 类型的函数，compute 函数本身的返回值类型为 float64。

在 main 函数中，定义了一个 `hypot` 变量，它是一个函数变量，入参为两个 float64 类型，返回值类型为 float64。

从后续的代码可以知道，hypot 变量可以当成函数名称以函数的形式直接调用，还可以当成函数调用参数传入 compute 函数。

## 方法（method）

在 Java 里面，很多时候将函数和方法这两个名词混为一谈，因为不管什么样的 Java 代码，首先就必须定义一个类，然后在类里面定义方法或者函数。但是在 Go 中，没有类这种概念，唯一接近的也就只有 struct，用来定义一种聚合多个字段的自定义类型，为了能够像 Java 类那样灵活的为类添加一些特定的逻辑，在 Go 也可以定义一些和类型绑定的函数 (function)，这种函数称为方法 (method)。

```go
package main

import (
    "fmt"
    "math"
)

type Vertex struct {
    X, Y float64
}

func (v Vertex) Abs() float64 {
    return math.Sqrt(v.X*v.X + v.Y*v.Y)
}

func main() {
    v := Vertex{3, 4}
    fmt.Println(v.Abs())
}
```

这里通过 `v.Abs()` 的方式调用了 Abs 方法，说明这里的 Abs 是 Vertex 这个类型才具有的方法。而定义方式就是在原来的函数定义语法中的函数名前面加上类型限制（比如 Vertex），以及对应类型的引用变量（比如 v）。

通过上面的代码，发现其实换个角度思考，函数的方法的区别不大，比如上面的 `Abs()` 方法，写成一个入参为 Vertex 类型的函数也是一样的。

### 基于类型指针的方法

先看一段代码。

```go
package main

import (
    "fmt"
    "math"
)

type Vertex struct {
    X, Y float64
}

func (v Vertex) Abs() float64 {
    v.X = 10
    return math.Sqrt(v.X*v.X + v.Y*v.Y)
}

func main() {
    v := Vertex{3, 4}
    fmt.Println(v.Abs())
    fmt.Println(v)
}
```

相对之前的代码，在 Abs 方法中增加了一行代码，将 v.X 修改为 10，最后的输出结果为：

```go
41.23105625617661
{30 40}
```

Abs 的方法到时和预期一样，但是执行完 Abs 方法之后再次输出 v 的值，发现依然是 `{30 40}`，这里和 Java 就不一样了，就会发现，在 Abs 方法里面对 v 的修改只在 Abs 方法内有效，也就是说，对于 Abs 方法来讲，拿到的 Vertex 变量的是基础数据类型一样的值传递。

那么，如果要修改 Vertex 类型的变量中的属性值要如何做？

我们需要为 Vertex 的指针变量定义一个方法，这样才能通过这个方法来实际修改 Vertex 变量的属性值。

```go
package main

import (
    "fmt"
    "math"
)

type Vertex struct {
    X, Y float64
}

func (v Vertex) Abs() float64 {
    return math.Sqrt(v.X*v.X + v.Y*v.Y)
}

func (v *Vertex) Scale(f float64) {
    v.X = v.X * f
    v.Y = v.Y * f
}

func main() {
    v := Vertex{3, 4}
    v.Scale(10)
    fmt.Println(v.Abs())
    fmt.Println(v)
}
```

```
50
{30 40}
```

发现 Scale 方法的定义有点不一样，在 Vertex 前面加上了 *，这种语法，是的 Scale 就可以真正修改 Vertex 变量 v 的属性值，在 Scale 方法中的 Vertex 就是引用传递。

和前面的 Abs 方法一样，Scale 一样也可以转换成普通的函数形式。

```go
package main

import (
    "fmt"
    "math"
)

type Vertex struct {
    X, Y float64
}

func Abs(v Vertex) float64 {
    return math.Sqrt(v.X*v.X + v.Y*v.Y)
}

func Scale(v *Vertex, f float64) {
    v.X = v.X * f
    v.Y = v.Y * f
}

func main() {
    v := Vertex{3, 4}
    Scale(&v, 10)
    fmt.Println(Abs(v))
}
```

Scale 方法接受的是 Vertex 的指针类型，以 `*Vertex` 的形式表示，调用的时候传入 Vertex 类型变量的指针就行 `&v`。

## Interface（接口）

Go 中的接口，不像 Java 那样还需要 `implements` 关键字来表明实现关系，在 Go 里面只要有和某个接口一样的方法，就可以认为实现了某个接口。

```go
package main

import (
    "fmt"
    "math"
)

type Abser interface {
    Abs() float64
}

func main() {
    var a Abser
    f := MyFloat(-math.Sqrt2)
    v := Vertex{3, 4}

    a = f  // a MyFloat implements Abser
    a = &v // a *Vertex implements Abser

    // In the following line, v is a Vertex (not *Vertex)
    // and does NOT implement Abser.
    a = v

    fmt.Println(a.Abs())
}

type MyFloat float64

func (f MyFloat) Abs() float64 {
    if f < 0 {
        return float64(-f)
    }
    return float64(f)
}

type Vertex struct {
    X, Y float64
}

func (v *Vertex) Abs() float64 {
    return math.Sqrt(v.X*v.X + v.Y*v.Y)
}
```

上面的代码定义了一个 `Abser` 接口，其中有一个 Abs() 方法。

MyFloat 类型有 Abs 方法，参数和返回值类型和 Abser 接口中的方法一致，那么 MyFloat 就实现了 Abser 接口。

*Vertex 也有 Abs 方法，参数和返回值类型跟 Abser 接口中的方法一致，所以 *Vertex 类型也实现了 Abser 接口，但上面的 `a = v` 这行代码依然会报错是因为，v 的类型是 Vertex 而不是 *Vertex 指针类型，这两者是有区别的。

> Go 中的接口也支持类似 Java 的多态的语法，即：变量定义成接口类型，实际赋值是具体实现的类型。

```go
package main

import "fmt"

type I interface {
    M()
}

type T struct {
    S string
}

func (t T) M() {
    fmt.Println(t.S)
}

func main() {
    var i I = T{"hello"}
    i.M()
}
```

### 空接口

```go
package main

import "fmt"

func main() {
    var i interface{}
    describe(i)

    i = 42
    describe(i)

    i = "hello"
    describe(i)
}

func describe(i interface{}) {
    fmt.Printf("(%v, %T)\n", i, i)
}
```

```
(<nil>, <nil>)
(42, int)
(hello, string)
```

空接口可以转换成任何类型。

## 类型判断

```go
package main

import "fmt"

func main() {
    var i interface{} = "hello"

    s := i.(string)
    fmt.Println(s)

    s, ok := i.(string)
    fmt.Println(s, ok)

    f, ok := i.(float64)
    fmt.Println(f, ok)

    f = i.(float64) // panic
    fmt.Println(f)
}
```

```
hello
hello true                                                      
0 false                                                         
panic: interface conversion: interface {} is string, not float64
```

语法是 `i.(T)`，其中 i 是变量名，T 是类型名称，这个语法用来判断 i 是否是 T 类型的变量，返回值有两个，第一个是 i 的输出值，第二个返回时判断结果，单独只接受第一个返回值时，如果类型判断失败会报错。

#### 通过 switch 语句匹配类型

```go
package main

import "fmt"

func do(i interface{}) {
    switch v := i.(type) {
    case int:
        fmt.Printf("Twice %v is %v\n", v, v*2)
    case string:
        fmt.Printf("%q is %v bytes long\n", v, len(v))
    default:
        fmt.Printf("I don't know about type %T!\n", v)
    }
}

func main() {
    do(21)
    do("hello")
    do(true)
}
```

```
Twice 21 is 42
"hello" is 5 bytes long
I don't know about type bool!
```

> Go 比较神奇的是在 switch 语句里面竟然还能类型比较，相对来说，Java 要做这样的操作时，代码就没那么好看了。

## Stringers

这是 Go 定义在 fmt 包下的接口，实现它的 String 方法，就像 Java 里面类实现 toString() 方法一样的用途。

```go
package main

import "fmt"

type Person struct {
    Name string
    Age  int
}

func (p Person) String() string {
    return fmt.Sprintf("%v (%v years)", p.Name, p.Age)
}

func main() {
    a := Person{"Arthur Dent", 42}
    z := Person{"Zaphod Beeblebrox", 9001}
    fmt.Println(a, z)
}
```

```
Arthur Dent (42 years) Zaphod Beeblebrox (9001 years)
```

## Goroutines

goroutines 是 Go 运行时的一个轻量级线程管理器。

```go
package main

import "fmt"

func say(str string) {
    for i := 0; i< 5; i++ {
        fmt.Println(str)
    }
}

func main(){
    go say("hello")
    say("world")
}
```

```go
hello
world
world
hello
hello
world
world
hello
hello
```

可以看见 hello 和 world 一直是在无序输出，就好像是两个线程，一个在输出 hello，一个在输出 world。

## channels（管道）

我的理解是，管道就像是一个线程间通信的桥梁，一段接收消息，一端发送消息。

```go
ch <- v // 将 v 发送到 管道 ch
v := <-ch // 将 ch 这个管道接收到的值赋值给变量 v
```

创建管道和创建 map 一样，需要调用 make() 函数：

```go
ch := make(chan int)
```

上面创建了一个收发 int 类型数据的管道。

```go
package main

import "fmt"

func sum(ch chan int, s []int) {
    sum := 0
    for _, i := range s {
        sum += i
    }
    ch <- sum
}

func main() {
    ch := make(chan int)
    s := []int{7, 2, 8, -9, 4, 0}
    go sum(ch, s[:len(s)/2])
    go sum(ch, s[len(s)/2:])
    x, y := <-ch, <-ch
    fmt.Println(x, y, x+y)
}
```

上面简单的结合 goroutines 使用了 channel。

* 定义 sum 方法，传入一个 int 类型的管道 ch 和一个 int 类型的 slices 变量 s，内部获取 s 所有元素的和，然后发送到 ch 管道。
* main 函数中首先创建了 int 类型的管道和 int 类型的 slices，然后启动两个 go 线程，分别去求 slices 前后两半的和，最后将 ch 管道接收的数据赋值给 x、y 并输出。

输出结果如下：

```
-5 17 12
```

### Buffered Channel

channel 定义的时候，支持定义管道的容量。

```go
ch := make(chan int, 2)
```

上面定义了一个容量为 2 的管道，ch 中最多只能容纳两条消息，不然就会抛出异常。

### channel 遍历

遍历 channle 和遍历 slices 的区别在于，slices 的 range 语法会返回元素下标和值，channel 的range 语法则只返回值。

### 关闭 channel

就像文件流一样，channel 使用完之后最好手动关闭，直接通过 close 函数关闭即可。

```go
close(ch)
```

## select

```go
package main

import "fmt"

func fibonacci(c, quit chan int) {
    x, y := 0, 1
    for {
        select {
        case c <- x:
            x, y = y, x+y
        case <-quit:
            fmt.Println("quit")
            return
        }
    }
}

func main() {
    c := make(chan int)
    quit := make(chan int)
    go func() {
        for i := 0; i < 10; i++ {
            fmt.Println(<-c)
        }
        quit <- 0
    }()
    fibonacci(c, quit)
}
```

select 换选择第一个可以执行的 case 执行，如果有多个 case 都可以执行，就随机选择一个。

上面的代码，因为在 main 函数里面启动的 go 线程会循环 10 次从 c 中获取数据，当 10 循环结束后，向 quit 管道发送信息。

在 fibonacci 函数中，死循环执行 select，因为 x、y 一直有效，所以 `c <- x` 一直是可执行的，所以肯定会一直执行，当 go 线程中循环结束后，不再有地方能处理 c 管道中的数据， fibonacci 中发送数据到 c 就会被阻塞，此时发现 `<-quit` 可以执行，程序顺势退出。

### default selection

前面讲到如果 select 的执行体中多个 case 都已经就绪时会随机选择一个执行，那如果都没有就绪时，如何处理呢？

Go 给了 select 一个默认的选项，如果没有任何一个 case 可执行，就执行 default 的逻辑：

```go
package main

import (
    "fmt"
    "time"
)

func main() {
    tick := time.Tick(100 * time.Millisecond)
    boom := time.After(500 * time.Millisecond)
    for {
        select {
        case <-tick:
            fmt.Println("tick.")
        case <-boom:
            fmt.Println("BOOM!")
            return
        default:
            fmt.Println("    .")
            time.Sleep(50 * time.Millisecond)
        }
    }
}
```

## sync.Mutex

> 终于又碰见了熟悉的并发锁！！！

我们已经知道 channels 如果进行 goroutines 之间的通信，但是如果我们不需要通信，只是需要确认在同一个时间只有一个 goroutines 在访问变量呢？

此时就需要一个互斥机制，提供这个机制的数据结构通常是 mutex。

Go 标准库提供了 `sync.Mutex` 来实现这种互斥机制，它有两个方法：

* Lock

* Unlock

接下来使用一个例子来解析它的用法。

> 本例取自于 [A Tour of Go](https://go.dev/tour/welcome/1)

```go
package main

import (
	"fmt"
	"sync"
	"time"
)

// SafeCounter is safe to use concurrently.
type SafeCounter struct {
	mu sync.Mutex
	v  map[string]int
}

// Inc increments the counter for the given key.
func (c *SafeCounter) Inc(key string) {
	c.mu.Lock()
	// Lock so only one goroutine at a time can access the map c.v.
	c.v[key]++
	c.mu.Unlock()
}

// Value returns the current value of the counter for the given key.
func (c *SafeCounter) Value(key string) int {
	c.mu.Lock()
	// Lock so only one goroutine at a time can access the map c.v.
	defer c.mu.Unlock()
	return c.v[key]
}

func main() {
	c := SafeCounter{v: make(map[string]int)}
	for i := 0; i < 1000; i++ {
		go c.Inc("somekey")
	}

	time.Sleep(time.Second)
	fmt.Println(c.Value("somekey"))
}
```

首先定义了一个 `SafeCounter` 类型，其中维护了一个 Mutex 锁变量 mu，和一个 map 变量 v。

SafeCounter 提供了两个方法， Inc 和 Value，因为这两个都需要考虑并发问题，所以这里的方法应该定义在 `*SafeCounter` 指针类型上，这样才能保证每个线程执行同一个 SafeCounter 变量相关逻辑是拿到的是同一个 Mutex 锁。

对于有显示 return 的方法，建议将锁释放放在 defer 语句中执行，以保证最终一定能释放锁。

## 一些题外话

### 设置 goproxy

Go 的仓库比较有意思的是，它是基于 github 实现的，使用 `go get` 指令就能从仓库中获取目标库，但是目前因为知名原因，国内无法访问，所以需要配置国内的 go 镜像地址。

```bash
$ go env -w GOPROXY=https://goproxy.cn,direct
```

这个镜像仓库好像是七牛云提供的来着，我忘了。

### GOPATH

基本上从云端下载的包都会存放到 `${GOPATH}/pkg` 目录下，这个默认是当前的用户目录下，也可以自己设置。

```bash
$ go env -w GOPATH=<your path>
```

### GO MODULE

开启 GO MODULE 指令：

```bash
$ go env -w GO111MODULE=on 
```

### 和 Java 对比

我不知道，Go 的话，我用的不多，学它只是因为 K8s 和 Docker 用这玩意儿写的。

不过执行 `go install` 之后竟然会根据操作系统的不同生成不同的可执行文件到 `${GOPATH}/bin` 目录下，这个倒是没想到的。
