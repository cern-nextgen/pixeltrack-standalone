from std.memory.arc_pointer import ArcPointer

from CUDACompat import CUDAStreamType
from Framework.ReusableObjectHolder import _HeldItem


# Equivalent to cms::cuda::SharedStreamPtr.
# In C++: shared_ptr<remove_pointer_t<cudaStream_t>> where a custom Deleter
# embedded in the control block returns the stream to the ReusableObjectHolder
# pool when the ref-count drops to zero.
# In Mojo: ArcPointer[_HeldItem[CUDAStreamType]] — _HeldItem.__del__ returns
# the stream to the pool, mirroring the C++ Deleter exactly.
alias SharedStreamPtr = ArcPointer[_HeldItem[CUDAStreamType]]
