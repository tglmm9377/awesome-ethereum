<!--TOC-->

<!--/TOC-->
## 数据类型
* EVM 虚拟机最大存储槽位2^256，每个槽位有256bits,如果使用uint8,EVM也会将剩余位用0补齐，补齐这一操作需要消耗gas。
* EVM的计算必须基于uint256，非uint256都会转换成uint256才进行计算。
> 注意：存储和转换是两回事,转换主要在计算时进行，但这两种情况都有需要消耗gas

## 硬编码的方式存储某些数据
* 使用constant 将变量存放到字节码，在字节码中的数据不需要通过SLOAD指令读取该指令消耗200gas
* 固定的计算可以直接采用hardcode的方式，没有必要存储在变量中

## SOLC 编译器对变量进行压缩
变量的顺序将影响编译器SSTORE的调用次数，SSTORE每次需要消耗2wgas
```
struct Car{
    uint64 amount;
    uint64 price;
    uint128 othervar1;
    uint256 othervar2;
}
Car car = car({
    amount:10,
    price: 1000000;
    othervar1: 1,
    othervar2:1
});

```
amount,price ,othervar1 总共占用256字节，编译器会将他们打包到一个槽位中，将othervar2打包到另一个槽位，此次SSTORE只调用两次。
这种原理不仅适用于在struct中，其他变量也适用。

## 汇编代码压缩变量
在大多数情况下减少gas开销的的思路可以理解为减少SSTORE的操作次数
```
 function package(uint64 a,uint64 b,uint64 c,uint64 d) internal pure returns(bytes32 result){
        assembly{
            let y := 0
            mstore(0x20,d)
            mstore(0x18,c)
            mstore(0x10,b)
            mstore(0x8,a)
            result := mload(0x20)
        }
    }
```
将四个uint64类型数据打包到一个32字节的bytes32返回，存储新返回的bytes32只需要一次SSTORE
对应的解包操作
```
function unpack(bytes32 result)public pure returns(uint64 a,uint64 b,uint64 c,uint64 d){
    assembly{
        d := result // 数据有32字节d变量只截取到后8字节
        mstore(0x18,result)
        a := mload(0)
        mstore(0x10,result)
        b := mload(0)
        mstore(0x8,result)
        c := mload(0)  // 每次将bytes32数据写入到offset为8字节的位置，从0位置读取相应的变量
       }
    }
```
mstore需要花费3*gas费用，mload 每次花费3gas
优点：这种方式只需要一次SLOAD就能获得所有变量的值,需要压缩的变量越多时此种方式节省的gas也越多
缺点：代码不易阅读，每次部署合约都需要引入package,unpack。

## 函数参数的合并压缩
通过上述方式将函数传递的参数进行打包，在一定程度上也会节省gas开销

## 默克尔树证明的特性减少存储的数据量
应用于存储固定的并且大量的配置信息时验证，输入的参数或者信息的若干值是否满足，而无需将所有配置信息进行存储一一比较

## IPFS
将大型的数据广播到IPFS上，合约中只需要存储对应hash值
当然也可以使用swarm代替

## 批量处理
这个优化属于代码层面的优化， 根据实际的使用场景将单次输入参数执行的函数，修改为支持调用一次可执行更多任务的方式
这样会降低 calldataload（3gas） 调用次数

## 结构体变量读写分离
```
contract structTest{
    struct obj{
        uint64 v1;
        uint64 v2;
        uint64 v3;
        uint64 v4;
    }
    obj obj1;
    function oldExam(uint64 a,uint64 b)public{
        uint a0;
        uint a1;
        uint a2;
        uint a3;
        uint a4;
        uint a5;
        uint b6;
        uint b5;
        uint b4;
        uint b3;
        uint b2;
        uint b1;
        obj1.v1 = a+b;
        obj1.v2 = a-b;
        obj1.v3 = a*b;
        obj1.v4 = a/b;
    }
    function setObj(uint64 v1_,uint64 v2_,uint64 v3_,uint64 v4_)public{
        obj1.v1 = v1_;
        obj1.v2 = v2_;
        obj1.v3 = v3_;
        obj1.v4 = v4_;
    }


    function newexam(uint64 a,uint64 b)public{
        uint a0;
        uint a1;
        uint a2;
        uint a3;
        uint a4;
        uint a5;
        uint b6;
        uint b5;
        uint b4;
        // uint b3;
        // uint b2;
        // uint b1;
      setObj(a+b,a-b,a*b,a/b);
    }
}
```
栈空间只能容纳16个本地变量，oldexam导致SOLC没有足够的栈空间优化SSTORE操作，
但是newexam不会导致栈被打满，编译器可以对SSTORE进行优化，只需要执行一次SSTORE指令，这种操作能有效降低gas消耗
经过测试可以节省 30000+gas花费。


## 直接访问内存比直接访问storage要节省gas
* uint8 num 变量直接可以更改为 uint256 num,因为在存储或者计算时候都需要将变量转换为uint256，每一个转换过程都需要消耗额外的gas
* uint256 value = data(一个来自storage的变量)，直接将value保存在一个内存变量中使用比每次在storage中读取消耗gas少的多
尤其是该变量使用次数大于2以上
* uint64 value = obj.v1 这种基于结构体的指针访问数据消耗相对于将变量直接存储在内存时候Gas消耗要高
uint64 v1 = obj.v1; 之后再obj.v1的使用中直接调用v1前提是obj的数据没有被修改。

## 基于SOLC的汇编代码优化
在编译SOL源码时候一定要开启选项 optimize-runs
### 
