//
//  TQueue.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

public struct TQueue<A> {
	let readEnd : TVar<[A]>
	let writeEnd : TVar<[A]>

	private init(_ readEnd : TVar<[A]>, _ writeEnd : TVar<[A]>) {
		self.readEnd = readEnd
		self.writeEnd = writeEnd
	}
	
	public func create() -> STM<TQueue<A>> {
		let read = TVar([] as [A])
		let write = TVar([] as [A])
		return STM<TQueue<A>>.pure(TQueue(read, write))
	}
	
	public func write(val : A) -> STM<()> {
		return self.writeEnd.read().flatMap { list in
			return self.writeEnd.write([val] + list)
		}
	}
}
