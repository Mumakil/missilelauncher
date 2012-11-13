sinon = require 'sinon'
chai = require 'chai'

expect = chai.expect

Missilelauncher = require '../lib/missilelauncher'

describe 'Missilelauncher', ->
  
  beforeEach ->
    @spy = sinon.spy()
    @clock = sinon.useFakeTimers()
    @device = write: @spy
    @missilelauncher = new Missilelauncher 
      device: @device
      config: 
        log: false
        FIRING_TIME: 100
        FULL_PITCH_TIME: 100
        FULL_TURN_TIME: 100
        MAX_HORIZONTAL_ANGLE: 90
        MIN_HORIZONTAL_ANGLE: -90
        MAX_VERTICAL_ANGLE: 45
        MIN_VERTICAL_ANGLE: -45
    
  afterEach ->
    @clock.restore()
    
  it 'should populate config', ->
    for property in ['FULL_VERTICAL_ANGLE', 'FULL_HORIZONTAL_ANGLE', 'HORIZONTAL_TURN_RATE', 'VERTICAL_TURN_RATE']
      expect(@missilelauncher.config[property]).to.be.a 'number'
    
  describe '#sendCommand', ->
    
    it 'should parse string commands', ->
      @missilelauncher.sendCommand 'UP'
      expect(@spy.called).to.equal true
    
    it 'should fail on everything else except string', ->
      expect(@missilelauncher.sendCommand {}).to.equal false
      expect(@spy.called).to.equal false
    
    it 'should send correct command', ->
      @missilelauncher.sendCommand 'STOP'
      expect(@spy.called).to.equal true
      expect(@spy.getCall(0).args[0][1]).to.equal 0x20
      
    it 'should work with lowercase command', ->
      @missilelauncher.sendCommand 'stop'
      expect(@spy.called).to.equal true
      expect(@spy.getCall(0).args[0][1]).to.equal 0x20
      
  describe 'commands', ->

    beforeEach ->
      sinon.spy @missilelauncher, 'sendCommand'
      
    afterEach ->
      @missilelauncher.sendCommand.restore()

    describe '#move', ->
      
      it 'should not move if already moving', ->
        @missilelauncher.busy = true
        expect(@missilelauncher.move 'UP', 100).to.be.undefined
        expect(@missilelauncher.sendCommand.called).to.equal false
        
      it 'should send command and stop after time', (done) ->
        ready = @missilelauncher.move 'UP', 100
        expect(@missilelauncher.busy).to.equal true
        expect(@missilelauncher.sendCommand.callCount).to.equal 1
        expect(@missilelauncher.sendCommand.getCall(0).args[0]).to.equal 'UP'
        @clock.tick(99)
        expect(@missilelauncher.sendCommand.callCount).to.equal 1
        @clock.tick(1)
        expect(@missilelauncher.busy).to.equal false
        expect(@missilelauncher.sendCommand.callCount).to.equal 2
        expect(@missilelauncher.sendCommand.getCall(1).args[0]).to.equal 'STOP'
        ready.then done

    describe '#fire', ->
      
      it 'should fire and resolve after firing timer has elapsed', (done) ->
        ready = @missilelauncher.fire()
        expect(@missilelauncher.busy).to.equal true
        expect(@missilelauncher.sendCommand.called).to.equal true
        expect(@missilelauncher.sendCommand.getCall(0).args[0]).to.equal 'FIRE'
        @clock.tick(99)
        expect(@missilelauncher.busy).to.equal true
        @clock.tick(1)
        expect(@missilelauncher.busy).to.equal false
        ready.then done
    
    describe '#pause', ->
      
      it 'should pause for specified time', (done) ->
        ready = @missilelauncher.pause(100)
        expect(@missilelauncher.busy).to.equal true
        @clock.tick(99)
        expect(@missilelauncher.busy).to.equal true
        @clock.tick(1)
        expect(@missilelauncher.busy).to.equal false
        ready.then done
        
  describe 'sequences', ->
    
    beforeEach ->
      sinon.spy @missilelauncher, 'sendCommand'
      
    afterEach ->
      @missilelauncher.sendCommand.restore()
    
    describe '#parseCommand', ->
      
      for cmd in ['UP 200', 'DOWN 200', 'LEFT 200', 'RIGHT 200', 'FIRE', 'PAUSE 200']
        do ->
          command = cmd
          it "should recognize command #{command} and return a promise returning function", (done) ->
            parsedCommand = @missilelauncher.parseCommand command
            expect(parsedCommand).to.be.a 'function'
            promise = parsedCommand()
            unless command.indexOf 'PAUSE' == 0
              expect(@missilelauncher.sendCommand.called).to.equal true
              expect(@missilelauncher.sendCommand.getCall(0).args[0]).to.equal command.split(' ')[0]
            expect(promise.then).to.be.a 'function'
            @clock.tick 200
            promise.then done
    
      it "should recognize command RESET and return a promise returning function", (done) ->
        parsedCommand = @missilelauncher.parseCommand 'RESET'
        expect(parsedCommand).to.be.a 'function'
        promise = parsedCommand()
        expect(promise.then).to.be.a 'function'
        @clock.tick 100
        process.nextTick => process.nextTick =>
          @clock.tick 100 
          process.nextTick =>
            promise.then done
    
    describe '#sequence', ->
      
      # Okay, this is some seriously ugly stuff, but since Q uses
      # process.nextTick we have to defer the logic here too
      it 'should parse the sequence and execute the commands', (done) ->
        promise = @missilelauncher.sequence [
          'UP 20'
          'DOWN 30'
          'LEFT 40'
          'PAUSE 50'
        ]
        expect(promise.then).to.be.a 'function'
        expect(@missilelauncher.busy).to.equal true
        expect(@missilelauncher.sendCommand.callCount).to.equal 1
        expect(@missilelauncher.sendCommand.getCall(0).args[0]).to.equal 'UP'
        @clock.tick 20
        expect(@missilelauncher.sendCommand.callCount).to.equal 2
        expect(@missilelauncher.sendCommand.getCall(1).args[0]).to.equal 'STOP'
        process.nextTick => process.nextTick =>
          expect(@missilelauncher.sendCommand.callCount).to.equal 3
          expect(@missilelauncher.sendCommand.getCall(2).args[0]).to.equal 'DOWN'
          @clock.tick 30
          expect(@missilelauncher.sendCommand.callCount).to.equal 4
          expect(@missilelauncher.sendCommand.getCall(3).args[0]).to.equal 'STOP'
          process.nextTick => process.nextTick =>
            expect(@missilelauncher.sendCommand.callCount).to.equal 5
            expect(@missilelauncher.sendCommand.getCall(4).args[0]).to.equal 'LEFT'
            @clock.tick 40
            expect(@missilelauncher.sendCommand.callCount).to.equal 6
            expect(@missilelauncher.sendCommand.getCall(5).args[0]).to.equal 'STOP'
            process.nextTick => process.nextTick =>
              @clock.tick 50
              process.nextTick =>
                expect(@missilelauncher.busy).to.equal false
                promise.then done
        