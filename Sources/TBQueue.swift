//
//  TBQueue.swift
//  Concurrent
//
//  Created by Robert Widmann on 9/27/15.
//  Copyright © 2015 TypeLift. All rights reserved.
//

public struct TBQueue<A> {
	let readNum : TVar<Int>
	let readHead : TVar<[A]>
	let writeNum : TVar<Int>
	let writeHead : TVar<[A]>

	private init(_ readNum : TVar<Int>, _ readHead : TVar<[A]>, _ writeNum : TVar<Int>, _ writeHead : TVar<[A]>) {
		self.readNum = readNum
		self.readHead = readHead
		self.writeNum = writeNum
		self.writeHead = writeHead
	}

	public init(n : Int) {
		let read = TVar([A]())
		let write = TVar([A]())
		let rsize = TVar(0)
		let wsize = TVar(n)
		self.init(rsize, read, wsize, write)
	}
	
	public static func create(n : Int) -> STM<TBQueue<A>> {
		let read = TVar([] as [A])
		let write = TVar([] as [A])
		let rsize = TVar(0)
		let wsize = TVar(n)
		return STM<TBQueue<A>>.pure(TBQueue(rsize, read, wsize, write))
	}
	
	public func write(x : A) -> STM<()> {
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
}
