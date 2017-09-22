//
//  TQueue.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015-2016 TypeLift. All rights reserved.
//

/// A `TQueue` is like a `TChan` in that it is a transactional channel however
/// it does not allow `duplicate()`s or `clone()`s.  Because of this, throughput
/// per individual operations is much faster.
///
/// The implementation is based on the traditional purely-functional queue
/// representation that uses two lists to obtain amortised O(1) enqueue and
/// dequeue operations.
public struct TQueue<A> {
	let readEnd : TVar<[A]>
	let writeEnd : TVar<[A]>

	private init(_ readEnd : TVar<[A]>, _ writeEnd : TVar<[A]>) {
		self.readEnd = readEnd
		self.writeEnd = writeEnd
	}

	public init() {
		self.readEnd = TVar([] as [A])
		self.writeEnd = TVar([] as [A])
	}

	/// Uses an atomic transaction to write the given value to the `TQueue`.
	///
	/// Blocks if the queue is full.
	public func write(_ val : A) -> STM<()> {
		return self.writeEnd.read().flatMap { list in
			return self.writeEnd.write([val] + list)
		}
	}

	/// Uses an atomic transaction to read the next value from the `TQueue`.
	public func read() -> STM<A> {
		return self.readEnd.read().flatMap { xs in
			if let x = xs.first {
				return self.readEnd.write(Array(xs.dropFirst()))
					.then(STM<A>.pure(x))
			}
			return self.writeEnd.read().flatMap { ys in
				if ys.isEmpty {
					return STM<A>.retry()
				}
				let zs = ys.reversed()
				if let z = zs.first {
					return self.writeEnd.write([]).then(self.readEnd.write(Array(zs.dropFirst()))).then(STM<A>.pure(z))
				}
				fatalError()
			}
		}
	}

	/// Uses an atomic transaction to read the next value from the `TQueue`
	/// without blocking or retrying on failure.
	public func tryRead() -> STM<Optional<A>> {
		return try! self.read().fmap(Optional.some).orElse(STM<A?>.pure(.none))
	}

	/// Uses an atomic transaction to get the next value from the `TQueue`
	/// without removing it, retrying if the queue is empty.
	public func peek() -> STM<A> {
		return self.read().flatMap { x in
			return self.unGet(x).then(STM<A>.pure(x))
		}
	}

	/// Uses an atomic transaction to get the next value from the `TQueue`
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
		return self.readEnd.read().flatMap { xs in
			return self.readEnd.write([x] + xs)
		}
	}

	/// Uses an STM transaction to return whether the channel is empty.
	public var isEmpty : STM<Bool> {
		return self.readEnd.read().flatMap { xs in
			if xs.isEmpty {
				return self.writeEnd.read().flatMap { ys in
					return STM<Bool>.pure(ys.isEmpty)
				}
			}
			return STM<Bool>.pure(false)
		}
	}
}
