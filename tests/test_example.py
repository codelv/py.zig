import pytest

def test_example():
    import pyzigtest
    assert pyzigtest.add(1, 2) == 3
    with pytest.raises(TypeError):
        pyzigtest.add(1)
    with pytest.raises(TypeError):
        pyzigtest.add(None, 1)
    assert pyzigtest.TEST_STR == "test!"
