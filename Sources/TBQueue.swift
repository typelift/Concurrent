//
//  TBQueue.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

/// `TBQueue` is a bounded version of `TQueue`. The queue has a maximum capacity
/// set when it is created. If the queue already contains the maximum number of 
/// elements, then `write()` blocks until an element is removed from the queue.
public struct TBQueue<A> {
	let readNum : TVar<Int>
	let readHead : TVar<[A]>
	let writeNum : TVar<Int>
	let writeHead : TVar<[A]>

	fileprivate init(_ readNum : TVar<Int>, _ readHead : TVar<[A]>, _ writeNum : TVar<Int>, _ writeHead : TVar<[A]>) {
		self.readNum = readNum
		self.readHead = readHead
		self.writeNum = writeNum
		self.writeHead = writeHead
	}

	/// Creates and initializes a new `TBQueue`.
	public init(n : Int) {
		let read = TVar([A]())
		let write = TVar([A]())
		let rsize = TVar(0)
		let wsize = TVar(n)
		self.init(rsize, read, wsize, write)
	}

	/// Uses an atomic transaction to create and initialize a new `TBQueue`.
	public static func create(_ n : Int) -> STM<TBQueue<A>> {
		let read = TVar([] as [A])
		let write = TVar([] as [A])
		let rsize = TVar(0)
		let wsize = TVar(n)
		return STM<TBQueue<A>>.pure(TBQueue(rsize, read, wsize, write))
	}

	/// Uses an atomic transaction to write the given value to the receiver.
	///
	/// Blocks if the queue is full.
	public func write(_ x : A) -> STM<()> {
		return self.writeNum.read().flatMap { w in
			let act : STM<()>
			if w != 0 {
				act = self.writeNum.write(w - 1)
			} else {
				act = self.readNum.read().flatMap { r in
					if r != 0 {
						return self.readNum.write(0).then(self.writeNum.write(r - 1))
					} else {
						return STM.retry()
					}
				}
			}
			
			return act.then(self.writeHead.read().flatMap { listend in
				return self.writeHead.write([x] + listend)
			})
		}
	}

	/// Uses an atomic transaction to read the next value from the receiver.
	public func read() -> STM<A> {
		return self.readHead.read().flatMap { xs in
			return self.readNum.read().flatMap { r in
				return self.readNum.write(r + 1)
					.then({
						if let x = xs.first {
							return self.readHead.write(Array(xs.dropFirst())).then(STM<A>.pure(x))
						}
						return self.writeHead.read().flatMap { ys in
							if ys.isEmpty {
								return STM<A>.retry()
							}
							let zs = ys.reversed()
							return self.writeHead.write([])
								.then(self.readHead.write(Array(zs.dropFirst())))
								.then(STM<A>.pure(ys.first!))
						}
					}())
			}
		}
	}

	/// Uses an atomic transaction to read the next value from the receiver
	/// without blocking or retrying on failure.
	public func tryRead() -> STM<Optional<A>> {
		return self.read().fmap(Optional.some).orElse(STM<A?>.pure(.none))
	}

	/// Uses an atomic transaction to get the next value from the receiver 
	/// without removing it, retrying if the queue is empty.
	public func peek() -> STM<A> {
		return self.read().flatMap { x in
			return self.unGet(x).then(STM<A>.pure(x))
		}
	}

	/// Uses an atomic transaction to get the next value from the receiver
	/// without removing it without retrying if the queue is empty.
	public func tryPeek() -> STM<Optional<A>> {
		return self.tryRead().flatMap { m in
			switch m {
			case let .some(x):
				return self.unGet(x).then(STM<A?>.pure(m))
			case .none:
				return STM<A?>.pure(.none)
			}
		}
	}

	/// Uses an atomic transaction to put a data item back onto a channel where
	/// it will be the next item read.
	///
	/// Blocks if the queue is full.
	public func unGet(_ x : A) -> STM<()> {
		return self.readNum.read().flatMap { r in
			return { () -> STM<()> in
				if r > 0 {
					return self.readNum.write((r - 1))
				}
				return self.writeNum.read().flatMap { w in
					if w > 0 {
						return self.writeNum.write((w - 1))
					}
					return STM<()>.retry()
				}
			}().then(self.readHead.read().flatMap { xs in
				return self.readHead.write([x] + xs)
			})
		}
	}

	/// Uses an STM transaction to return whether the channel is empty.
	public var isEmpty : STM<Bool> {
		return self.readHead.read().flatMap { xs in
			if xs.isEmpty {
				return self.writeHead.read().flatMap { ys in
					return STM<Bool>.pure(ys.isEmpty)
				}
			}
			return STM<Bool>.pure(false)
		}
	}

	/// Uses an STM transaction to return whether the channel is full.
	public var isFull : STM<Bool> {
		return self.writeNum.read().flatMap { w in
			if w > 0 {
				return STM<Bool>.pure(false)
			}
			return self.readNum.read().flatMap { r in
				return STM<Bool>.pure(r <= 0)
			}
		}
	}
}
