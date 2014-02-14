#!/usr/bin/env ruby

logger = Log4r::Logger.new('carb')
logger.outputters << Log4r::Outputter.stdout
logger.outputters << Log4r::FileOutputter.new('carb', :filename =>  'carb.log')

def debug(message)
  logger.debug(message)
end

def info(message)
  logger.info(message)
end

def warn(message)
  logger.warn(message)
end

def error(message)
  logger.error(message)
end

def fatal(message)
  logger.fatal(message)
end
