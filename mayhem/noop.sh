# Example mayhem agent that does nothing but print some messages

function run()
{
    local pause="5"
    while true;
    do
        echo "🐵 Hello World!"
        sleep "${pause}"
    done
}

function cleanup()
{
    echo "🐵 Goodbye World!"
}
