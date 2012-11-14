sinon = require 'sinon'
chai = require 'chai'

expect = chai.expect

Missilelauncher = require '../src/missilelauncher'

describe 'Missilelauncher', ->
  
  beforeEach ->
    @stub = sinon.stub()
    @clock = sinon.useFakeTimers()
    @device = write: @stub
    @missilelauncher = new Missilelauncher 
      device: @device
      config: 
        log: false
        time:
          fire: 100
          fullTurn: 100
          fullPitch: 100
        angle:
          horizontal: 
            max: 90
            min: -90
          vertical:
            max: 45
            min: -45
    
  afterEach ->
    @clock.restore()
    
  it 'should populate config', ->
    config = 
      log: false
      time:
        fire: 100
        fullTurn: 100
        fullPitch: 100
      angle:
        horizontal: 
          max: 90
          min: -90
          rate: 100 / 180
          full: 180
        vertical:
          max: 45
          min: -45
          rate: 100 / 90
          full: 90
    expect(@missilelauncher.config).to.deep.equal config
    
  describe '#sendCommand', ->
    
    it 'should parse string commands', ->
      @missilelauncher.sendCommand 'UP'
      expect(@stub.called).to.be.true
    
    it 'should fail on everything else except string', ->
      expect(@missilelauncher.sendCommand {}).to.be.false
      expect(@stub.called).to.be.false
    
    it 'should send correct command', ->
      @missilelauncher.sendCommand 'STOP'
      expect(@stub.called).to.be.true
      expect(@stub.getCall(0).args[0][1]).to.equal 0x20
      
    it 'should work with lowercase command', ->
      @missilelauncher.sendCommand 'stop'
      expect(@stub.called).to.be.true
      expect(@stub.getCall(0).args[0][1]).to.equal 0x20
      
  describe 'command', ->

    beforeEach ->
      sinon.stub @missilelauncher, 'sendCommand'
      
    afterEach ->
      @missilelauncher.sendCommand.restore()

    describe '#move', ->
      
      it 'should not move if already moving', ->
        @missilelauncher.busy = true
        expect(@missilelauncher.move 'UP', 100).to.be.undefined
        expect(@missilelauncher.sendCommand.called).to.be.false
        
      it 'should send command and stop after time', (done) ->
        @missilelauncher.sendCommand.withArgs 'UP'
        @missilelauncher.sendCommand.withArgs 'STOP'
        ready = @missilelauncher.move 'UP', 100
        expect(@missilelauncher.busy).to.be.true
        expect(@missilelauncher.sendCommand.withArgs('UP').calledOnce).to.be.true
        @clock.tick(99)
        expect(@missilelauncher.sendCommand.withArgs('STOP').called).to.be.false
        @clock.tick(1)
        expect(@missilelauncher.busy).to.be.false
        expect(@missilelauncher.sendCommand.withArgs('STOP').calledOnce).to.be.true
        ready.then done

    describe '#fire', ->
      
      it 'should fire and resolve after firing timer has elapsed', (done) ->
        ready = @missilelauncher.fire()
        expect(@missilelauncher.busy).to.be.true
        expect(@missilelauncher.sendCommand.called).to.be.true
        expect(@missilelauncher.sendCommand.getCall(0).args[0]).to.equal 'FIRE'
        @clock.tick(99)
        expect(@missilelauncher.busy).to.be.true
        @clock.tick(1)
        expect(@missilelauncher.busy).to.be.false
        ready.then done
    
    describe '#pause', ->
      
      it 'should pause for specified time', (done) ->
        ready = @missilelauncher.pause(100)
        expect(@missilelauncher.busy).to.be.true
        @clock.tick(99)
        expect(@missilelauncher.busy).to.be.true
        @clock.tick(1)
        expect(@missilelauncher.busy).to.be.false
        ready.then done
        
  describe 'sequences', ->
    
    beforeEach ->
      sinon.spy @missilelauncher, 'move'
      sinon.stub @missilelauncher, 'sendCommand'
      
    afterEach ->
      @missilelauncher.move.restore()
      @missilelauncher.sendCommand.restore()
    
    describe '#parseCommand', ->
      
      for cmd in ['UP', 'DOWN', 'LEFT', 'RIGHT']
        do ->
          command = cmd
          it "should recognize command #{command} and return a promise returning function", ->
            @missilelauncher.move.withArgs(command, 100)
            parsedCommand = @missilelauncher.parseCommand "#{command} 100"
            expect(parsedCommand).to.be.a 'function'
            promise = parsedCommand()
            expect(promise.then).to.be.a 'function'
            expect(@missilelauncher.move.withArgs(command, 100))
    
      it 'should recognize command PAUSE and call it', ->
        sinon.spy(@missilelauncher, 'pause').withArgs(200)
        parsedCommand = @missilelauncher.parseCommand 'PAUSE 200'
        expect(parsedCommand).to.be.a 'function'
        promise = parsedCommand()
        expect(promise.then).to.be.a 'function'
        expect(@missilelauncher.pause.withArgs(200).calledOnce).to.be.true
        @missilelauncher.pause.restore()
    
      it "should recognize command RESET and return a promise returning function", ->
        sinon.spy @missilelauncher, 'reset'
        parsedCommand = @missilelauncher.parseCommand 'RESET'
        expect(parsedCommand).to.be.a 'function'
        promise = parsedCommand()
        expect(promise.then).to.be.a 'function'
        expect(@missilelauncher.reset.calledOnce).to.be.true
        @missilelauncher.reset.restore()
    
    describe '#sequence', ->
      
      beforeEach ->
        spy = @missilelauncher.move
        spy.withArgs('UP', 20)
        spy.withArgs('DOWN', 30)
        spy.withArgs('LEFT', 40)
        sinon.spy(@missilelauncher, 'pause').withArgs(50)
        @missilelauncher.sendCommand.withArgs('STOP')
      
      it 'should parse the sequence and execute the commands', (done) ->
        promise = @missilelauncher.sequence [
          'UP 20'
          'DOWN 30'
          'LEFT 40'
          'PAUSE 50'
        ]
        expect(promise.then).to.be.a 'function'
        expect(@missilelauncher.busy).to.be.true
        expect(@missilelauncher.move.withArgs('UP', 20).calledOnce).to.be.true
        @clock.tick 20
        expect(@missilelauncher.sendCommand.withArgs('STOP').calledOnce).to.be.true
        process.nextTick => process.nextTick =>
          expect(@missilelauncher.move.withArgs('DOWN', 30).calledOnce).to.be.true
          @clock.tick 30
          expect(@missilelauncher.sendCommand.withArgs('STOP').calledTwice).to.be.true
          process.nextTick => process.nextTick =>
            expect(@missilelauncher.move.withArgs('LEFT', 40).calledOnce).to.be.true
            @clock.tick 40
            expect(@missilelauncher.sendCommand.withArgs('STOP').calledThrice).to.be.true
            process.nextTick => process.nextTick =>
              @clock.tick 50
              process.nextTick =>
                expect(@missilelauncher.busy).to.be.false
                promise.then done
    
    describe '#reset', ->
      
      beforeEach ->
        @missilelauncher.move.withArgs('DOWN', 100)
        @missilelauncher.move.withArgs('LEFT', 100)
      
      it 'should turn maximum left and maximum down', (done) ->
        @missilelauncher.reset().then done
        @clock.tick 100
        process.nextTick => process.nextTick =>
          @clock.tick 100
          expect(@missilelauncher.move.withArgs('DOWN', 100).calledOnce).to.be.true
          expect(@missilelauncher.move.withArgs('LEFT', 100).calledOnce).to.be.true
        
      it 'should reset turret directions', (done) ->
        @missilelauncher.reset().then done
        @clock.tick 100
        process.nextTick => process.nextTick =>
          @clock.tick 100
          expect(@missilelauncher.direction).to.deep.equal vertical: -45, horizontal: -90

  describe 'angular commands', ->
    
    beforeEach ->
      sinon.spy @missilelauncher, 'move'
      
    afterEach ->
      @missilelauncher.move.restore()
      
    describe '#zero', ->
      
      beforeEach ->
        sinon.spy @missilelauncher, 'reset'
        sinon.spy(@missilelauncher, 'pointTo').withArgs(0,0)
        
      afterEach ->
        @missilelauncher.reset.restore()
        @missilelauncher.pointTo.restore()

      it 'should call first reset and then point to 0,0, ending in (0,0)', (done) ->
        @missilelauncher.zero().then done
        expect(@missilelauncher.reset.calledOnce).to.be.true
        @clock.tick 100 # Reset, vertical
        process.nextTick => process.nextTick =>
          @clock.tick 100 # Reset, horizontal
          process.nextTick => process.nextTick =>
            expect(@missilelauncher.pointTo.withArgs(0,0).calledOnce).to.be.true
            process.nextTick => process.nextTick =>
              @clock.tick 50 # Zero, vertical
              process.nextTick => process.nextTick =>
                @clock.tick 50 # Zero, horizontal
                expect(@missilelauncher.direction).to.deep.equal vertical: 0, horizontal: 0
                
    describe '#turnBy', ->
      
      beforeEach ->
        @missilelauncher.direction.horizontal = 0
      
      it 'should return promise', ->
        expect(@missilelauncher.turnBy(1).then).to.be.a 'function'
      
      it 'should turn left on negative angles', ->
        @missilelauncher.move.withArgs('LEFT')
        @missilelauncher.turnBy(-10)
        expect(@missilelauncher.move.withArgs('LEFT').calledOnce).to.be.true
        expect(@missilelauncher.direction.horizontal).to.equal -10
        
      it 'should turn right on positive angles', ->
        @missilelauncher.move.withArgs('RIGHT')
        @missilelauncher.turnBy(10)
        expect(@missilelauncher.move.withArgs('RIGHT').calledOnce).to.be.true
        expect(@missilelauncher.direction.horizontal).to.equal 10
        
      it 'should calculate correct time for turning', ->
        @missilelauncher.move.withArgs('RIGHT', 50)
        @missilelauncher.turnBy 90
        expect(@missilelauncher.move.withArgs('RIGHT', 50).calledOnce).to.be.true
        
    describe '#pitchBy', ->

      beforeEach ->
        @missilelauncher.direction.vertical = 0

      it 'should return promise', ->
        expect(@missilelauncher.pitchBy(1).then).to.be.a 'function'

      it 'should turn down on negative angles', ->
        @missilelauncher.move.withArgs('DOWN')
        @missilelauncher.pitchBy(-10)
        expect(@missilelauncher.move.withArgs('DOWN').calledOnce).to.be.true
        expect(@missilelauncher.direction.vertical).to.equal -10

      it 'should turn up on positive angles', ->
        @missilelauncher.move.withArgs('UP')
        @missilelauncher.pitchBy(10)
        expect(@missilelauncher.move.withArgs('UP').calledOnce).to.be.true
        expect(@missilelauncher.direction.vertical).to.equal 10

      it 'should calculate correct time for turning', ->
        @missilelauncher.move.withArgs('UP', 50)
        @missilelauncher.pitchBy 45
        expect(@missilelauncher.move.withArgs('UP', 50).calledOnce).to.be.true
        
    describe '#pointTo', ->
      
      beforeEach ->
        @missilelauncher.direction = 
          vertical: 0
          horizontal: 0
        sinon.spy @missilelauncher, 'turnBy'
        sinon.spy @missilelauncher, 'pitchBy'
        
      afterEach ->
        @missilelauncher.turnBy.restore()
        @missilelauncher.pitchBy.restore()
        
      it 'should turn only to maximum available', (done) ->
        @missilelauncher.pitchBy.withArgs(45)
        @missilelauncher.turnBy.withArgs(90)
        @missilelauncher.pointTo(180, 180).then done
        @clock.tick(100)
        process.nextTick => process.nextTick =>
          @clock.tick(100)
          expect(@missilelauncher.pitchBy.withArgs(45).calledOnce).to.be.true
          expect(@missilelauncher.turnBy.withArgs(90).calledOnce).to.be.true
        
      it 'should turn only to minimum available', (done) ->
        @missilelauncher.pitchBy.withArgs(-45)
        @missilelauncher.turnBy.withArgs(-90)
        @missilelauncher.pointTo(horizontal: -180, vertical: -180).then done
        @clock.tick(100)
        process.nextTick => process.nextTick =>
          @clock.tick(100)
          expect(@missilelauncher.pitchBy.withArgs(-45).calledOnce).to.be.true
          expect(@missilelauncher.turnBy.withArgs(-90).calledOnce).to.be.true
    
    describe '#fireAt', ->
      
      beforeEach ->
        @missilelauncher.direction = 
          vertical: 0
          horizontal: 0
        sinon.spy @missilelauncher, 'pointTo'
        sinon.spy @missilelauncher, 'fire'
        
      afterEach ->
        @missilelauncher.pointTo.restore()
        @missilelauncher.fire.restore()
        
      it 'should turn and fire', (done) ->
        @missilelauncher.pointTo.withArgs(10, 20)
        @missilelauncher.fireAt(10, 20).then done
        expect(@missilelauncher.pointTo.withArgs(10, 20).calledOnce).to.be.true
        @clock.tick(100)
        process.nextTick => process.nextTick =>
          @clock.tick(100)
          process.nextTick => process.nextTick =>
            expect(@missilelauncher.fire.calledOnce).to.be.true
            @clock.tick(100)