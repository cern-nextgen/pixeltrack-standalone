from std.memory.arc_pointer import ArcPointer
from os.atomic import Atomic

from MojoBridge.ConcurrentQueue import ConcurrentQueue

# -*- Mojo -*-
#
# Package:     FWCore/Utilities
# Class  :     ReusableObjectHolder
#
# \class edm::ReusableObjectHolder ReusableObjectHolder "ReusableObjectHolder.h"
#
# Description: Thread safe way to do create and reuse a group of the same object type.
#
# Usage:
# This class can be used to safely reuse a series of objects created on demand. The reuse
# of the objects is safe even across different threads since one can safely call all member
# functions of this class on the same instance of this class from multiple threads.
#
# This class manages the cache of reusable objects and therefore an instance of this
# class must live as long as you want the cache to live.
#
# The primary way of using the class it to call makeOrGetAndClear
# An example use would be
#
#   var objectToUse = makeOrGetAndClear(holder, factory)
#
# If you always want to set the values you can use makeOrGet
#
#   var objectToUse = makeOrGet(holder, maker)
#   objectToUse.setValue(3)
#
# NOTE: If you hold onto the Arc until another call to the ReusableObjectHolder,
# make sure to release the Arc before the call. That way the object you were just
# using can go back into the cache and be reused for the call you are going to make.
# An example
#
#   while someCondition():
#       var obj = holder.tryToGet()
#       obj.value().setValue(someNewValue())
#       useTheObject(obj.value())
#       # obj goes out of scope, Arc ref count drops to zero,
#       # _HeldItem.__del__ fires and returns the item to the cache
#
#
# Original Author:  Chris Jones
#         Created:  Fri, 31 July 2014 14:29:41 GMT
#
# Ported to Mojo by Abbas Naim
#


trait ReusableObjectMaker:
    alias Output: Copyable & ImplicitlyDestructible

    def make(mut self) -> Self.Output:
        ...


trait ReusableObjectFactory:
    alias Output: Copyable & ImplicitlyDestructible

    def make(mut self) -> Self.Output:
        ...

    def clear(mut self, ref item: Self.Output):
        ...


# Equivalent to the shared_ptr<T> with custom deleter returned by C++ tryToGet.
# When the last Arc reference drops, __del__ fires and returns the item to the
# pool via the back-pointer, mirroring the lambda in addBack.
struct _HeldItem[T: Copyable & ImplicitlyDestructible](Movable):
    var _item: Optional[Self.T]
    var _holder: UnsafePointer[ReusableObjectHolder[Self.T], MutAnyOrigin]

    fn __init__(
        out self,
        var item: Optional[Self.T],
        holder: UnsafePointer[ReusableObjectHolder[Self.T], MutAnyOrigin],
    ):
        self._item = item^
        self._holder = holder

    fn __moveinit__(out self, deinit take: Self):
        self._item = take._item^
        self._holder = take._holder

    fn __del__(var self):
        # mirrors: pHolder->addBack(std::unique_ptr<T,Deleter>{iItem, deleter})
        # Empty Arc (null item) does nothing, mirroring empty shared_ptr destructor.
        if self._item:
            self._holder[]._addBack(self._item.take())


struct ReusableObjectHolder[T: Copyable & ImplicitlyDestructible](Movable):
    var m_availableQueue: ConcurrentQueue[Self.T]
    var m_outstandingObjects: Atomic[DType.int64]

    fn __init__(out self):
        self.m_availableQueue = ConcurrentQueue[Self.T]()
        self.m_outstandingObjects = Atomic[DType.int64](0)

    fn __moveinit__(out self, deinit take: Self):
        debug_assert(take.m_outstandingObjects.load() == 0, "ReusableObjectHolder moved while items are still outstanding")
        self.m_availableQueue = take.m_availableQueue^
        self.m_outstandingObjects = Atomic[DType.int64](0)

    fn __del__(var self):
        debug_assert(self.m_outstandingObjects.load() == 0, "ReusableObjectHolder destroyed while items are still outstanding")
        # m_availableQueue drops here automatically, destroying all held items

    # Adds the item to the cache.
    # Use this function if you know ahead of time
    # how many cached items you will need.
    fn add(mut self, var item: Self.T):
        self.m_availableQueue.enqueue(item^)

    # Tries to get an already created object.
    # If none are available, returns None (equivalent to empty shared_ptr<T>{}).
    # If one is available, returns ArcPointer[_HeldItem[T]] whose destructor automatically
    # returns the item to the pool — equivalent to shared_ptr<T> with custom deleter.
    # Use this function in conjunction with add().
    fn tryToGet(mut self) -> Optional[ArcPointer[_HeldItem[Self.T]]]:
        var item = self.m_availableQueue.dequeue()
        if item:
            _ = self.m_outstandingObjects.fetch_add(1)
            return ArcPointer[_HeldItem[Self.T]](
                _HeldItem[Self.T](item^, UnsafePointer(to=self))
            )
        return None

    # Private — mirrors C++ addBack, called only by _HeldItem.__del__.
    fn _addBack(mut self, var item: Self.T):
        self.m_availableQueue.enqueue(item^)
        _ = self.m_outstandingObjects.fetch_sub(1)

    # Remove all idle items from the pool.
    fn clear(mut self):
        while self.m_availableQueue.dequeue():
            pass


fn makeOrGet[FM: ReusableObjectMaker](
    mut holder: ReusableObjectHolder[FM.Output], mut iMakeFunc: FM
) raises -> ArcPointer[_HeldItem[FM.Output]]:
    var returnValue = holder.tryToGet()
    while not returnValue:
        holder.add(iMakeFunc.make())
        returnValue = holder.tryToGet()
    return returnValue.take()


fn makeOrGetAndClear[FM: ReusableObjectFactory](
    mut holder: ReusableObjectHolder[FM.Output], mut iFactory: FM
) raises -> ArcPointer[_HeldItem[FM.Output]]:
    var returnValue = holder.tryToGet()
    while not returnValue:
        holder.add(iFactory.make())
        returnValue = holder.tryToGet()

    iFactory.clear(returnValue.value()[]._item.value())
    return returnValue.take()
