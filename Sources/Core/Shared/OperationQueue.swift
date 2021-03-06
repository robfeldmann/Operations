//
//  OperationQueue.swift
//  Operations
//
//  Created by Daniel Thorpe on 26/06/2015.
//  Copyright (c) 2015 Daniel Thorpe. All rights reserved.
//

import Foundation

/**
A protocol which the `OperationQueue`'s delegate must conform to. The delegate is informed
when the queue is about to add an operation, and when operations finish. Because it is a
delegate protocol, conforming types must be classes, as the queue weakly owns it.
*/
public protocol OperationQueueDelegate: class {

    /**
    The operation queue will add a new operation. This is for information only, the
    delegate cannot affect whether the operation is added, or other control flow.

    - paramter queue: the `OperationQueue`.
    - paramter operation: the `NSOperation` instance about to be added.
    */
    func operationQueue(queue: OperationQueue, willAddOperation operation: NSOperation)

    /**
    An operation has finished on the queue.

    - parameter queue: the `OperationQueue`.
    - parameter operation: the `NSOperation` instance which finished.
    - parameter errors: an array of `ErrorType`s.
    */
    func operationQueue(queue: OperationQueue, willFinishOperation operation: NSOperation, withErrors errors: [ErrorType])

    /**
     An operation has finished on the queue.

     - parameter queue: the `OperationQueue`.
     - parameter operation: the `NSOperation` instance which finished.
     - parameter errors: an array of `ErrorType`s.
     */
    func operationQueue(queue: OperationQueue, didFinishOperation operation: NSOperation, withErrors errors: [ErrorType])
}

/**
An `NSOperationQueue` subclass which supports the features of Operations. All functionality
is achieved via the overridden functionality of `addOperation`.
*/
public class OperationQueue: NSOperationQueue {

    /**
    The queue's delegate, helpful for reporting activity.

    - parameter delegate: a weak `OperationQueueDelegate?`
    */
    public weak var delegate: OperationQueueDelegate? = .None

    /**
    Adds the operation to the queue. Subclasses which override this method must call this
    implementation as it is critical to how Operations function.

    - parameter op: an `NSOperation` instance.
    */
    // swiftlint:disable function_body_length
    public override func addOperation(operation: NSOperation) {
        if let operation = operation as? Operation {

            /// Add an observer so that any produced operations are added to the queue
            /// Except for group operations, where any produced operations are added
            /// to the the group.
            operation.addObserver(ProducedOperationObserver { [weak self] op, produced in
                if let group = op as? GroupOperation {
                    group.addOperation(produced)
                }
                else {
                    self?.addOperation(produced)
                }
            })

            /// Add an observer to invoke the will finish delegate method
            operation.addObserver(WillFinishObserver { [weak self] operation, errors in
                if let q = self {
                    q.delegate?.operationQueue(q, willFinishOperation: operation, withErrors: errors)
                }
            })

            /// Add an observer to invoke the did finish delegate method
            operation.addObserver(DidFinishObserver { [weak self] operation, errors in
                if let q = self {
                    q.delegate?.operationQueue(q, didFinishOperation: operation, withErrors: errors)
                }
            })

            /// Process any conditions
            if operation.conditions.count > 0 {

                /// Check for mutual exclusion conditions
                let manager = ExclusivityManager.sharedInstance
                let mutuallyExclusiveConditions = operation.conditions.filter { $0.mutuallyExclusive }
                var previousMutuallyExclusiveOperations = Set<NSOperation>()
                for condition in mutuallyExclusiveConditions {
                    let category = "\(condition.category)"
                    if let previous = manager.addOperation(operation, category: category) {
                        previousMutuallyExclusiveOperations.insert(previous)
                    }
                }

                // Create the condition evaluator
                let evaluator = operation.evaluateConditions()

                // Get the condition dependencies
                let indirectDependencies = operation.indirectDependencies

                // If there are dependencies
                if indirectDependencies.count > 0 {

                    // Iterate through the indirect dependencies
                    indirectDependencies.forEach {

                        // Indirect dependencies are executed after
                        // any previous mutually exclusive operation(s)
                        $0.addDependencies(previousMutuallyExclusiveOperations)

                        // Indirect dependencies are executed after
                        // all direct dependencies
                        $0.addDependencies(operation.directDependencies)

                        // Only evaluate conditions after all indirect
                        // dependencies have finished
                        evaluator.addDependency($0)
                    }

                    // Add indirect dependencies
                    addOperations(indirectDependencies)
                }

                // Add the evaluator
                addOperation(evaluator)
            }

            // Indicate to the operation that it is to be enqueued
            operation.willEnqueue()
        }
        else {
            operation.addCompletionBlock { [weak self, weak operation] in
                if let queue = self, op = operation {
                    queue.delegate?.operationQueue(queue, didFinishOperation: op, withErrors: [])
                }
            }
        }
        // swiftlint:enable function_body_length

        delegate?.operationQueue(self, willAddOperation: operation)

        super.addOperation(operation)
    }

    /**
    Adds the operations to the queue.

    - parameter ops: an array of `NSOperation` instances.
    - parameter wait: a Bool flag which is ignored.
    */
    public override func addOperations(ops: [NSOperation], waitUntilFinished wait: Bool) {
        ops.forEach(addOperation)
    }
}


public extension NSOperationQueue {

    /**
     Add operations to the queue as an array
     - parameters ops: a array of `NSOperation` instances.
     */
    func addOperations<S where S: SequenceType, S.Generator.Element: NSOperation>(ops: S) {
        addOperations(Array(ops), waitUntilFinished: false)
    }

    /**
     Add operations to the queue as a variadic parameter
     - parameters ops: a variadic array of `NSOperation` instances.
    */
    func addOperations(ops: NSOperation...) {
        addOperations(ops)
    }
}
